import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let holdToRecord = Self("holdToRecord")
}

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Speech Recognition") {
                Picker("Model", selection: $settings.selectedModel) {
                    ForEach(WhisperModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }

                Picker("Language", selection: $settings.selectedLanguage) {
                    ForEach(WhisperLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
            }

            Section("Shortcut") {
                KeyboardShortcuts.Recorder("Hold to record:", name: .holdToRecord)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 280)
    }
}
