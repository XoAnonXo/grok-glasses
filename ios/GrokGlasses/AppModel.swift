import Foundation
import SwiftUI
import MWDATCore

@MainActor
final class AppModel: ObservableObject {
  @Published var token: String = Keychain.load() ?? ""
  @Published var registration: String = "unknown"
  @Published var controller: GlassesController

  init() {
    controller = GlassesController(client: ServerClient(token: Keychain.load() ?? ""))
    observeRegistration()
  }

  func saveToken() {
    Keychain.save(token)
    controller.client = ServerClient(token: token)
  }

  func register() {
    Task { try? await Wearables.shared.startRegistration() }
  }

  private func observeRegistration() {
    Task {
      for await state in Wearables.shared.registrationStateStream() {
        await MainActor.run { self.registration = "\(state)" }
      }
    }
  }
}
