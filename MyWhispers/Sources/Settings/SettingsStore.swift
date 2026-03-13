import SwiftUI

@Observable
@MainActor
final class SettingsStore {
    @ObservationIgnored
    @AppStorage("selectedModel") private var _selectedModel: WhisperModel = .small

    @ObservationIgnored
    @AppStorage("selectedLanguage") private var _selectedLanguage: WhisperLanguage = .auto

    @ObservationIgnored
    @AppStorage("preferredLanguages") private var _preferredLanguagesData: Data = {
        // Default: English and French
        (try? JSONEncoder().encode([WhisperLanguage.english, WhisperLanguage.french])) ?? Data()
    }()

    @ObservationIgnored
    @AppStorage("launchAtLogin") private var _launchAtLogin: Bool = false

    @ObservationIgnored
    @AppStorage("streamingMode") private var _streamingMode: Bool = false

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

    var preferredLanguages: [WhisperLanguage] {
        get {
            access(keyPath: \.preferredLanguages)
            guard let decoded = try? JSONDecoder().decode([WhisperLanguage].self, from: _preferredLanguagesData) else {
                return [.english, .french]
            }
            return decoded
        }
        set {
            withMutation(keyPath: \.preferredLanguages) {
                _preferredLanguagesData = (try? JSONEncoder().encode(newValue)) ?? Data()
            }
        }
    }

    func isPreferredLanguage(_ language: WhisperLanguage) -> Bool {
        preferredLanguages.contains(language)
    }

    func togglePreferredLanguage(_ language: WhisperLanguage) {
        var current = preferredLanguages
        if let index = current.firstIndex(of: language) {
            current.remove(at: index)
        } else {
            current.append(language)
        }
        preferredLanguages = current
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

    var streamingMode: Bool {
        get {
            access(keyPath: \.streamingMode)
            return _streamingMode
        }
        set {
            withMutation(keyPath: \.streamingMode) {
                _streamingMode = newValue
            }
        }
    }
}
