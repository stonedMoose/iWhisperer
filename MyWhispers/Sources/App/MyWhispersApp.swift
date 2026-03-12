import SwiftUI

@main
struct MyWhispersApp: App {
    @State private var settingsStore = SettingsStore()

    var body: some Scene {
        MenuBarExtra("MyWhispers", systemImage: "mic") {
            Text("Ready")

            Divider()

            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit MyWhispers") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(settingsStore)
        }
    }
}
