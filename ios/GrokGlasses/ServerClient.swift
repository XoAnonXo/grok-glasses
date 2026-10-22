import Foundation
import UIKit

/// Talks only to our xAI-backed Cloudflare Worker. No AI key lives in the app.
struct ServerClient {
  var base = "https://grok-glasses-server.conscious-carnation.workers.dev"
  var token: String

  // Cloudflare returns 1010 for odd User-Agents, so present a browser-like UA.
  private static let userAgent =
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1 GrokGlasses/1.0"

  struct StateResp: Decodable {
    let scene: String
    let sceneAt: Double
    let lastReply: String
    struct Turn: Decodable { let role: String; let text: String; let at: Double; let bot: String? }
    let history: [Turn]
    struct BotReply: Decodable { let id: String?; let bot: String; let text: String; let at: Double }
    struct PendingAsk: Decodable { let id: String; let text: String; let bot: String; let at: Double; let status: String }
    let botReply: BotReply?
    let pendingAsk: PendingAsk?
  }

  static let bots = ["Grok Bot", "Gmail bot", "Helpoooor", "GelatoBot",
                     "Dubizzle Bot", "Rightsverse Growth", "Research bot Aeralyte", "Corporate Aeralyte"]

  private func request(_ path: String, method: String, json: [String: Any]?, withToken: Bool) throws -> URLRequest {
    guard let url = URL(string: base + path) else { throw URLError(.badURL) }
    var r = URLRequest(url: url)
    r.httpMethod = method
    r.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
    if json != nil { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    if withToken { r.setValue(token, forHTTPHeaderField: "X-Glasses-Token") }
    if let json { r.httpBody = try JSONSerialization.data(withJSONObject: json) }
    r.timeoutInterval = 30
    return r
  }

  private func text(from data: Data) -> String? {
    (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["text"] as? String
  }

  /// POST /frame — body matches server/core.mjs: {image: dataURL, hash}. Token required.
  @discardableResult
  func sendFrame(jpeg: Data, hash: String) async throws -> String? {
    let dataURL = "data:image/jpeg;base64," + jpeg.base64EncodedString()
    let req = try request("/frame", method: "POST", json: ["image": dataURL, "hash": hash], withToken: true)
    let (data, resp) = try await URLSession.shared.data(for: req)
    if let http = resp as? HTTPURLResponse, http.statusCode == 429 { return nil } // rate-limited / duplicate
    return text(from: data)
  }

  /// POST /chat — {text} -> {text}. Not token-gated on the server.
  func chat(_ message: String) async throws -> String? {
    let req = try request("/chat", method: "POST", json: ["text": message], withToken: false)
    let (data, _) = try await URLSession.shared.data(for: req)
    return text(from: data)
  }

  /// POST /ask {text, bot} -> {id, status}. Token-gated. Routes to the user's Grok Bot bots.
  struct AskResult { let id: String?; let status: String }
  func ask(_ message: String, bot: String) async throws -> AskResult {
    let req = try request("/ask", method: "POST", json: ["text": message, "bot": bot], withToken: true)
    let (data, _) = try await URLSession.shared.data(for: req)
    let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    return AskResult(id: obj["id"] as? String, status: (obj["status"] as? String) ?? "error")
  }

  /// GET /state -> {scene, sceneAt, lastReply, botReply, pendingAsk, history}
  func state() async throws -> StateResp {
    let req = try request("/state", method: "GET", json: nil, withToken: false)
    let (data, _) = try await URLSession.shared.data(for: req)
    return try JSONDecoder().decode(StateResp.self, from: data)
  }
}

/// Cheap 64-bit dHash so we can skip near-duplicate frames before uploading.
enum ImageHash {
  static func dhash(_ image: UIImage) -> String {
    let w = 9, h = 8
    let size = CGSize(width: w, height: h)
    UIGraphicsBeginImageContextWithOptions(size, true, 1)
    image.draw(in: CGRect(origin: .zero, size: size))
    let small = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    guard let cg = small?.cgImage else { return "" }
    var pixels = [UInt8](repeating: 0, count: w * h)
    let cs = CGColorSpaceCreateDeviceGray()
    guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w, space: cs,
                              bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return "" }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    var bits: UInt64 = 0
    for row in 0..<h {
      for col in 0..<(w - 1) {
        bits <<= 1
        if pixels[row * w + col] > pixels[row * w + col + 1] { bits |= 1 }
      }
    }
    return String(format: "%016llx", bits)
  }

  static func hamming(_ a: String, _ b: String) -> Int {
    guard let x = UInt64(a, radix: 16), let y = UInt64(b, radix: 16) else { return 64 }
    return (x ^ y).nonzeroBitCount
  }
}
