import ServiceManagement
import SwiftUI

@main
struct MacWhispererApp: App {
    @State private var settingsStore: SettingsStore
    @State private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    init() {
        let store = SettingsStore()
        _settingsStore = State(initialValue: store)
        _appState = State(initialValue: AppState(settingsStore: store))
        L10n.current = store.appLanguage
    }

    var body: some Scene {
        MenuBarExtra {
            // Status
            if !appState.micPermissionGranted {
                Label(L10n.microphoneNotAuthorized, systemImage: "exclamationmark.triangle")
                Button(L10n.openMicrophoneSettings) {
                    appState.openMicrophoneSettings()
                }
            } else if !appState.accessibilityPermissionGranted {
                Label(L10n.accessibilityNotAuthorized, systemImage: "exclamationmark.triangle")
                Button(L10n.openAccessibilitySettings) {
                    appState.openAccessibilitySettings()
                }
                Button(L10n.restartApp) {
                    appState.relaunch()
                }
            } else if appState.isMeetingProcessing {
                Text(appState.meetingStatusMessage.isEmpty ? L10n.processingMeeting : appState.meetingStatusMessage)
            } else if appState.isMeetingRecording {
                let elapsed = Int(appState.meetingElapsedTime)
                let m = elapsed / 60
                let s = elapsed % 60
                Text(L10n.recordingMeeting(m, s))
            } else if appState.isProcessing {
                Text(L10n.transcribing)
            } else if appState.isRecording {
                Text(L10n.recording)
            } else if appState.isDownloadingModel {
                Text(L10n.downloadingModel(appState.downloadingModelName, Int(appState.downloadProgress * 100)))
            } else if !appState.isModelLoaded {
                Text(L10n.loadingModel)
            } else {
                Text(L10n.ready)
            }

            Divider()

            if !appState.micPermissionGranted || !appState.accessibilityPermissionGranted {
                Button(L10n.recheckPermissions) {
                    appState.recheckPermissions()
                }
                Divider()
            }

            // Microphone quick-switch
            let inputDevices = AudioDeviceManager.listInputDevices()
            if !inputDevices.isEmpty {
                Section("Microphone") {
                    Button {
                        settingsStore.selectedMicrophoneUID = ""
                    } label: {
                        Text("System Default \(settingsStore.selectedMicrophoneUID.isEmpty ? "✓" : "")")
                    }
                    ForEach(inputDevices) { device in
                        Button {
                            settingsStore.selectedMicrophoneUID = device.uid
                        } label: {
                            Text("\(device.name) \(settingsStore.selectedMicrophoneUID == device.uid ? "✓" : "")")
                        }
                    }
                }
            }

            // Language quick-switch
            Section(L10n.language) {
                Button {
                    settingsStore.selectedLanguage = .auto
                } label: {
                    Text("\(L10n.autoDetect) \(settingsStore.selectedLanguage == .auto ? "✓" : "")")
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
            Section(L10n.meeting) {
                if appState.isMeetingRecording {
                    Button(L10n.stopMeetingRecording) {
                        Task {
                            await appState.toggleMeetingRecording()
                        }
                    }
                } else if appState.isMeetingProcessing {
                    Text(L10n.transcribingMeeting)
                    Button(L10n.cancelTranscription) {
                        appState.cancelMeetingTranscription()
                    }
                } else {
                    Button(L10n.startMeetingRecording) {
                        Task {
                            await appState.toggleMeetingRecording()
                        }
                    }
                    .disabled(appState.isRecording || appState.isProcessing)
                }
            }

            Divider()

            Button("Streaming (Beta) \(settingsStore.streamingMode ? "✓" : "")") {
                settingsStore.streamingMode.toggle()
            }
            .disabled(appState.isRecording || appState.isProcessing)

            Button("\(L10n.launchAtLogin) \(settingsStore.launchAtLogin ? "✓" : "")") {
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

            Button(L10n.settings) {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button(L10n.quitWhisperer) {
                Task {
                    await appState.prepareForTermination()
                    NSApplication.shared.terminate(nil)
                }
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            MenuBarIconView(
                isMeetingRecording: appState.isMeetingRecording,
                isRecording: appState.isRecording,
                isProcessing: appState.isProcessing,
                isMeetingProcessing: appState.isMeetingProcessing,
                language: settingsStore.selectedLanguage
            )
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(settingsStore)
                .environment(appState)
        }

        Window(L10n.setupWelcomeTitle, id: "setup") {
            SetupView {
                appState.showSetupWindow = false
            }
            .environment(appState)
            .environment(settingsStore)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .onChange(of: appState.showSetupWindow) { _, show in
            if show {
                openWindow(id: "setup")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }
}
