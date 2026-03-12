import ServiceManagement
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
                .onChange(of: settings.selectedModel) { _, _ in
                    NotificationCenter.default.post(name: .modelChanged, object: nil)
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
                    .onChange(of: settings.launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            settings.launchAtLogin = !newValue
                            print("Failed to update login item: \(error)")
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 280)
    }
}

extension Notification.Name {
    static let modelChanged = Notification.Name("modelChanged")
}
