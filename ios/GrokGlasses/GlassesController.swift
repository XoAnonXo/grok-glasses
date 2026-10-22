import Foundation
import UIKit
import AVFoundation
import MWDATCore
import MWDATCamera
import MWDATDisplay
import MWDATMockDevice
import MWDATSpeech

/// Drives one DeviceSession with Camera + Display (+ optional Speech) on the
/// Ray-Ban Display glasses, bridging frames and chat through our Worker.
@MainActor
final class GlassesController: ObservableObject {
  @Published var sceneText = ""
  @Published var replyText = ""
  @Published var botReplyText = ""
  @Published var status = "Idle"
  @Published var streaming = false

  private let wearables = Wearables.shared
  private var session: DeviceSession?
  private var camera: Camera?
  private var display: Display?
  private var speech: Speech?

  private let tokens = ListenerTokenBag()
  private var pollTask: Task<Void, Never>?
  private var lastUpload = Date.distantPast
  private var lastHash = ""
  private let synth = AVSpeechSynthesizer()
  private var lastSpoken = ""

  var client: ServerClient

  init(client: ServerClient) { self.client = client }

  // MARK: - Lifecycle

  func start() async {
    status = "Connecting…"
    do {
      let selector = AutoDeviceSelector(wearables: wearables, filter: { $0.supportsDisplay() })
      let session = try wearables.createSession(deviceSelector: selector)
      self.session = session

      let started = Task {
        for await state in session.stateStream() where state == .started { return }
      }
      try session.start()
      await started.value

      await attachDisplay(session)
      await attachCamera(session)
      startPolling()
      status = "Connected"
    } catch {
      status = "Error: \(error.localizedDescription)"
    }
  }

  func stop() {
    pollTask?.cancel(); pollTask = nil
    tokens.clear()
    speech?.stop(); speech = nil
    camera?.stop(); camera = nil
    display?.stop(); display = nil
    session?.stop(); session = nil
    streaming = false
    status = "Stopped"
  }

  // MARK: - Display

  private func attachDisplay(_ session: DeviceSession) async {
    do {
      let display = try session.addDisplay()
      self.display = display
      display.statePublisher.listen { [weak self] state in
        guard state == .started else { return }
        Task { @MainActor in await self?.renderCards() }
      }.store(in: tokens)
      display.start()
    } catch {
      status = "Display error: \(error.localizedDescription)"
    }
  }

  private func renderCards() async {
    guard let display else { return }
    let scene = sceneText.isEmpty ? "waiting…" : sceneText
    let reply = replyText.isEmpty ? "—" : replyText
    do {
      try await display.send(
        FlexBox(direction: .column, spacing: 8) {
          MWDATDisplay.Text("Grok sees", style: .heading)
          MWDATDisplay.Text(scene, style: .body)
          MWDATDisplay.Text("Grok says", style: .heading)
          MWDATDisplay.Text(reply, style: .body)
        }
        .padding(16)
        .background(.card)
      )
    } catch {
      NSLog("[GrokGlasses] display.send failed: \(error)")
    }
  }

  // MARK: - Camera

  private func attachCamera(_ session: DeviceSession) async {
    do {
      if try await wearables.checkPermissionStatus(.camera) != .granted {
        guard try await wearables.requestPermission(.camera) == .granted else {
          status = "Camera permission denied"; return
        }
      }
      let config = StreamConfiguration(videoCodec: .raw, resolution: .medium, frameRate: 7)
      guard let camera = try session.addCamera(config: config) else { return }
      self.camera = camera
      let stream = camera.stream
      stream.statePublisher.listen { [weak self] state in
        Task { @MainActor in self?.streaming = (state == .streaming) }
      }.store(in: tokens)
      stream.videoFramePublisher.listen { [weak self] frame in
        guard let image = frame.makeUIImage() else { return }
        Task { @MainActor in self?.handleFrame(image) }
      }.store(in: tokens)
      stream.errorPublisher.listen { error in
        NSLog("[GrokGlasses] stream error: \(error.localizedDescription)")
      }.store(in: tokens)
      stream.start()
    } catch {
      status = "Camera error: \(error.localizedDescription)"
    }
  }

  private func handleFrame(_ image: UIImage) {
    // Throttle to ~1 frame / 2s.
    guard Date().timeIntervalSince(lastUpload) >= 2.0 else { return }
    let hash = ImageHash.dhash(image)
    if !lastHash.isEmpty && ImageHash.hamming(hash, lastHash) <= 4 { return } // skip near-duplicate
    guard let jpeg = downscaledJPEG(image, maxDim: 768) else { return }
    lastUpload = Date()
    lastHash = hash
    Task {
      if let text = try? await client.sendFrame(jpeg: jpeg, hash: hash), !text.isEmpty {
        await MainActor.run { self.sceneText = text }
        await renderCards()
      }
    }
  }

  private func downscaledJPEG(_ image: UIImage, maxDim: CGFloat) -> Data? {
    let s = min(1, maxDim / max(image.size.width, image.size.height))
    let size = CGSize(width: image.size.width * s, height: image.size.height * s)
    let renderer = UIGraphicsImageRenderer(size: size)
    let out = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    return out.jpegData(compressionQuality: 0.7)
  }

  // MARK: - Speech (experimental)

  func startSpeech() async {
    guard let session else { return }
    do {
      if try await wearables.checkPermissionStatus(.microphone) != .granted {
        guard try await wearables.requestPermission(.microphone) == .granted else {
          status = "Mic permission denied"; return
        }
      }
      guard let speech = try session.addSpeech() else { return }
      self.speech = speech
      speech.transcriptionPublisher.listen { [weak self] result in
        guard result.isFinal else { return }
        Task { @MainActor in await self?.ask(result.text) }
      }.store(in: tokens)
      speech.start()
      status = "Listening…"
    } catch {
      status = "Speech error: \(error.localizedDescription)"
    }
  }

  // MARK: - Ask bots

  func askBots(_ text: String, bot: String) async {
    let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return }
    botReplyText = "(\(bot) is thinking…)"
    do {
      let res = try await client.ask(q, bot: bot)
      if res.status == "relay_not_configured" {
        botReplyText = "(relay not configured on the server yet)"
      }
    } catch {
      status = "Ask error: \(error.localizedDescription)"
    }
  }

  // MARK: - Chat

  func ask(_ text: String) async {
    let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return }
    if let reply = try? await client.chat(q), !reply.isEmpty {
      replyText = reply
      await renderCards()
      speak(reply)
    }
  }

  private func speak(_ text: String) {
    guard text != lastSpoken else { return }
    lastSpoken = text
    let u = AVSpeechUtterance(string: text)
    u.voice = AVSpeechSynthesisVoice(language: "en-US")
    synth.speak(u)
  }

  // MARK: - Polling /state

  private func startPolling() {
    pollTask?.cancel()
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        if let self, let st = try? await self.client.state() {
          await MainActor.run {
            if !st.scene.isEmpty { self.sceneText = st.scene }
            if !st.lastReply.isEmpty { self.replyText = st.lastReply }
            if let br = st.botReply { self.botReplyText = "\(br.bot): \(br.text)" }
          }
          await self.renderCards()
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
      }
    }
  }
}
