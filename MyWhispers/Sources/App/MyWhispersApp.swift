import SwiftUI

@main
struct MyWhispersApp: App {
    @State private var settingsStore: SettingsStore
    @State private var appState: AppState

    init() {
        let store = SettingsStore()
        _settingsStore = State(initialValue: store)
        _appState = State(initialValue: AppState(settingsStore: store))
    }

    var body: some Scene {
        MenuBarExtra("MyWhispers", systemImage: appState.isRecording ? "mic.fill" : "mic") {
            // Status
            if !appState.micPermissionGranted {
                Label("Microphone not authorized", systemImage: "exclamationmark.triangle")
                Button("Open Microphone Settings...") {
                    appState.openMicrophoneSettings()
                }
            } else if !appState.accessibilityPermissionGranted {
                Label("Accessibility not authorized", systemImage: "exclamationmark.triangle")
                Button("Open Accessibility Settings...") {
                    appState.openAccessibilitySettings()
                }
            } else if appState.isProcessing {
                Text("Transcribing...")
            } else if appState.isRecording {
                Text("Recording...")
            } else if !appState.isModelLoaded {
                Text("Loading model...")
            } else {
                Text("Ready")
            }

            Divider()

            if !appState.micPermissionGranted || !appState.accessibilityPermissionGranted {
                Button("Recheck Permissions") {
                    appState.recheckPermissions()
                }
                Divider()
            }

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
