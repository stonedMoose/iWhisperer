import ServiceManagement
import SwiftUI

@main
struct MyWhispersApp: App {
    @State private var settingsStore: SettingsStore
    @State private var appState: AppState
    @Environment(\.openSettings) private var openSettings

    init() {
        let store = SettingsStore()
        _settingsStore = State(initialValue: store)
        _appState = State(initialValue: AppState(settingsStore: store))
    }

    var body: some Scene {
        MenuBarExtra("MyWhispers", systemImage: "waveform") {
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
                Button("Restart App (required after granting)") {
                    appState.relaunch()
                }
            } else if appState.isMeetingProcessing {
                Text(appState.meetingStatusMessage.isEmpty ? "Processing meeting..." : appState.meetingStatusMessage)
            } else if appState.isMeetingRecording {
                let elapsed = Int(appState.meetingElapsedTime)
                let m = elapsed / 60
                let s = elapsed % 60
                Text("Recording meeting \(String(format: "%d:%02d", m, s))")
            } else if appState.isProcessing {
                Text("Transcribing...")
            } else if appState.isRecording {
                Text("Recording...")
            } else if appState.isDownloadingModel {
                Text("Downloading model - \(appState.downloadingModelName) - \(Int(appState.downloadProgress * 100))%")
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

            // Language quick-switch
            Section("Language") {
                Button {
                    settingsStore.selectedLanguage = .auto
                } label: {
                    Text("Auto-detect \(settingsStore.selectedLanguage == .auto ? "✓" : "")")
                }

                ForEach(settingsStore.preferredLanguages) { language in
                    Button {
                        settingsStore.selectedLanguage = language
                    } label: {
                        Text("\(language.displayName) \(settingsStore.selectedLanguage == language ? "✓" : "")")
                    }
                }
            }

            // Meeting
            Section("Meeting") {
                if appState.isMeetingRecording {
                    Button("Stop Meeting Recording") {
                        Task {
                            await appState.toggleMeetingRecording()
                        }
                    }
                } else if appState.isMeetingProcessing {
                    Text("Transcribing meeting...")
                    Button("Cancel Transcription") {
                        appState.cancelMeetingTranscription()
                    }
                } else if !appState.isWhisperXInstalled {
                    Button("Install WhisperX...") {
                        Task {
                            await appState.installWhisperX()
                        }
                    }
                    .disabled(appState.isMeetingProcessing)
                } else {
                    Button("Start Meeting Recording") {
                        Task {
                            await appState.toggleMeetingRecording()
                        }
                    }
                    .disabled(appState.isRecording || appState.isProcessing)
                }
            }

            Divider()

            Button("Lancer au démarrage \(settingsStore.launchAtLogin ? "✓" : "")") {
                settingsStore.launchAtLogin.toggle()
                do {
                    if settingsStore.launchAtLogin {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    settingsStore.launchAtLogin.toggle()
                }
            }

            Divider()

            Button("Settings...") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
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
