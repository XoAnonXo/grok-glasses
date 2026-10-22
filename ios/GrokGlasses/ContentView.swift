import SwiftUI

struct ContentView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var controller: GlassesController
  @State private var question = ""
  @State private var selectedBot = ServerClient.bots.first!
  @State private var askBots = false

  init(model: AppModel) {
    self.model = model
    self.controller = model.controller
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Server token") {
          SecureField("Glasses token", text: $model.token)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          Button("Save token") { model.saveToken() }
        }

        Section("Glasses") {
          LabeledContent("Registration", value: model.registration)
          LabeledContent("Status", value: controller.status)
          Button("Register with Meta AI") { model.register() }
          Button(controller.streaming ? "Stop" : "Start camera + display") {
            if controller.streaming { controller.stop() }
            else { Task { await controller.start() } }
          }
          Button("Ask by voice (experimental)") {
            Task { await controller.startSpeech() }
          }
        }

        Section("Grok sees") { Text(controller.sceneText.isEmpty ? "—" : controller.sceneText) }
        Section("Grok says") { Text(controller.replyText.isEmpty ? "—" : controller.replyText) }
        Section("Bot says") { Text(controller.botReplyText.isEmpty ? "—" : controller.botReplyText) }

        Section("Ask") {
          Toggle("Ask bots (otherwise Grok vision chat)", isOn: $askBots)
          if askBots {
            Picker("Bot", selection: $selectedBot) {
              ForEach(ServerClient.bots, id: \.self) { Text($0) }
            }
          }
          TextField("Type a question", text: $question)
          Button("Send") {
            let q = question; question = ""
            if askBots { Task { await controller.askBots(q, bot: selectedBot) } }
            else { Task { await controller.ask(q) } }
          }
        }
      }
      .navigationTitle("Grok Glasses")
    }
  }
}
