import SwiftUI

@Observable
@MainActor
final class SettingsStore {
    @ObservationIgnored
    @AppStorage("selectedModel") private var _selectedModel: WhisperModel = .small

    @ObservationIgnored
    @AppStorage("selectedLanguage") private var _selectedLanguage: WhisperLanguage = .auto

    @ObservationIgnored
    @AppStorage("launchAtLogin") private var _launchAtLogin: Bool = false

    var selectedModel: WhisperModel {
        get {
            access(keyPath: \.selectedModel)
            return _selectedModel
        }
        set {
            withMutation(keyPath: \.selectedModel) {
                _selectedModel = newValue
            }
        }
    }

    var selectedLanguage: WhisperLanguage {
        get {
            access(keyPath: \.selectedLanguage)
            return _selectedLanguage
        }
        set {
            withMutation(keyPath: \.selectedLanguage) {
                _selectedLanguage = newValue
            }
        }
    }

    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return _launchAtLogin
        }
        set {
            withMutation(keyPath: \.launchAtLogin) {
                _launchAtLogin = newValue
            }
        }
    }
}
