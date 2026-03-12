import SwiftUI

@main
struct MyWhispersApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("MyWhispers", systemImage: "mic.fill") {
            Text("MyWhispers")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
