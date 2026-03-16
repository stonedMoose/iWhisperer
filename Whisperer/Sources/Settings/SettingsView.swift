import OSLog
import ServiceManagement
import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let holdToRecord = Self("holdToRecord")
    static let meetingRecord = Self("meetingRecord")
}

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var settings = settings

        HStack(alignment: .top, spacing: 0) {
            // Column 1: General
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.general, systemImage: "gearshape")
                        .font(.headline)

                    Toggle(L10n.launchAtLogin, isOn: $settings.launchAtLogin)
                        .onChange(of: settings.launchAtLogin) { _, newValue in
                            do {
                                if newValue {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                settings.launchAtLogin = !newValue
                                Log.general.error("Failed to update login item: \(error)")
                            }
                        }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.appLanguage, systemImage: "globe")
                        .font(.headline)

                    Picker("", selection: $settings.appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.model, systemImage: "cpu")
                        .font(.headline)

                    Picker("", selection: $settings.selectedModel) {
                        ForEach(WhisperModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: settings.selectedModel) { _, _ in
                        NotificationCenter.default.post(name: .modelChanged, object: nil)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.settingsPermissions, systemImage: "lock.shield")
                        .font(.headline)

                    HStack(spacing: 6) {
                        Image(systemName: appState.micPermissionGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(appState.micPermissionGranted ? .green : .red)
                        Text(L10n.settingsMicrophone)
                        Spacer()
                        if !appState.micPermissionGranted {
                            Button(L10n.setupGrant) {
                                appState.openMicrophoneSettings()
                            }
                            .controlSize(.small)
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: appState.accessibilityPermissionGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(appState.accessibilityPermissionGranted ? .green : .red)
                        Text(L10n.settingsAccessibility)
                        Spacer()
                        if !appState.accessibilityPermissionGranted {
                            Button(L10n.setupGrant) {
                                appState.openAccessibilitySettings()
                            }
                            .controlSize(.small)
                        }
                    }

                    Button(L10n.settingsShowSetupGuide) {
                        openWindow(id: "setup")
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                    .font(.caption)
                }

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Column 2: Languages
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.preferredLanguages, systemImage: "globe")
                        .font(.headline)

                    Text(L10n.preferredLanguagesCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(WhisperLanguage.allCases.filter { $0 != .auto }) { language in
                            Toggle(language.displayName, isOn: Binding(
                                get: { settings.isPreferredLanguage(language) },
                                set: { _ in settings.togglePreferredLanguage(language) }
                            ))
                            .toggleStyle(.checkbox)
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Column 3: Insert at Caret
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.insertAtCaret, systemImage: "keyboard")
                        .font(.headline)

                    Text(L10n.insertAtCaretCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    KeyboardShortcuts.Recorder(for: .holdToRecord)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.streaming, systemImage: "antenna.radiowaves.left.and.right")
                        .font(.headline)

                    Toggle(L10n.enableStreamingMode, isOn: $settings.streamingMode)

                    Text(L10n.streamingCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Column 4: Meeting
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L10n.meeting, systemImage: "person.3")
                            .font(.headline)

                        Text(L10n.meetingCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        KeyboardShortcuts.Recorder(for: .meetingRecord)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label(L10n.transcriptLocation, systemImage: "folder")
                            .font(.headline)

                        HStack {
                            Text(settings.transcriptDirectory.lastPathComponent)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(L10n.choose) {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                panel.directoryURL = settings.transcriptDirectory
                                if panel.runModal() == .OK, let url = panel.url {
                                    settings.transcriptDirectory = url
                                }
                            }
                        }

                        Text(L10n.transcriptLocationCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label(L10n.aiRefinement, systemImage: "sparkles")
                            .font(.headline)

                        Toggle(L10n.refineTranscriptWithAI, isOn: $settings.refinementEnabled)

                        if settings.refinementEnabled {
                            Picker(L10n.provider, selection: $settings.refinementProvider) {
                                ForEach(LLMProvider.allCases) { provider in
                                    Text(provider.displayName).tag(provider)
                                }
                            }
                            .onChange(of: settings.refinementProvider) { _, newValue in
                                settings.refinementModel = newValue.defaultModel
                            }

                            if settings.refinementProvider.requiresAPIKey {
                                SecureField(L10n.apiKey, text: $settings.refinementAPIKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            TextField(L10n.model, text: $settings.refinementModel)
                                .textFieldStyle(.roundedBorder)

                            Text(L10n.prompt)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextEditor(text: $settings.refinementPrompt)
                                .font(.caption)
                                .frame(minHeight: 120)
                                .border(Color.secondary.opacity(0.3))

                            Button(L10n.resetPromptToDefault) {
                                settings.refinementPrompt = SettingsStore.defaultRefinementPrompt
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 920, height: 480)
    }
}

extension Notification.Name {
    static let modelChanged = Notification.Name("modelChanged")
}
