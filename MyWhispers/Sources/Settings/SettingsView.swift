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

    var body: some View {
        @Bindable var settings = settings

        HStack(alignment: .top, spacing: 0) {
            // Column 1: General
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("General", systemImage: "gearshape")
                        .font(.headline)

                    Picker("Model", selection: $settings.selectedModel) {
                        ForEach(WhisperModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .onChange(of: settings.selectedModel) { _, _ in
                        NotificationCenter.default.post(name: .modelChanged, object: nil)
                    }

                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
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
                    Label("HuggingFace", systemImage: "key")
                        .font(.headline)

                    SecureField("Token", text: $settings.hfToken)
                        .textFieldStyle(.roundedBorder)

                    Link("Get a token at huggingface.co",
                         destination: URL(string: "https://huggingface.co/settings/tokens")!)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Required for speaker identification.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label("Preferred Languages", systemImage: "globe")
                        .font(.headline)

                    Text("Shown in the menu bar for quick switching.")
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

            // Column 2: Insert at Caret
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Insert at Caret", systemImage: "keyboard")
                        .font(.headline)

                    KeyboardShortcuts.Recorder("Shortcut:", name: .holdToRecord)

                    Text("Hold shortcut to record, release to transcribe and insert text at cursor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label("Streaming", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.headline)

                    Toggle("Enable streaming mode", isOn: $settings.streamingMode)

                    Text("Type text progressively as you speak instead of waiting until you stop recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Column 3: Meeting
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Meeting", systemImage: "person.3")
                        .font(.headline)

                    KeyboardShortcuts.Recorder("Shortcut:", name: .meetingRecord)

                    Text("Press to start recording, press again to stop and transcribe with speaker labels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label("Transcript Location", systemImage: "folder")
                        .font(.headline)

                    HStack {
                        Text(settings.transcriptDirectory.lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose...") {
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

                    Text("Meeting transcripts are saved here automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 750, height: 480)
    }
}

extension Notification.Name {
    static let modelChanged = Notification.Name("modelChanged")
}
