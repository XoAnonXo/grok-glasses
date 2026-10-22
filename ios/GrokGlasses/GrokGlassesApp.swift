import SwiftUI
import MWDATCore

@main
struct GrokGlassesApp: App {
  @StateObject private var model = AppModel()

  init() {
    do { try Wearables.configure() }
    catch { NSLog("[GrokGlasses] Wearables.configure failed: \(error)") }
  }

  var body: some Scene {
    WindowGroup {
      ContentView(model: model)
        .onOpenURL { url in
          guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
          else { return }
          Task {
            do { _ = try await Wearables.shared.handleUrl(url) }
            catch { NSLog("[GrokGlasses] handleUrl failed: \(error)") }
          }
        }
    }
  }
}
