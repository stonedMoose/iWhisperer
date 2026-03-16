import Security
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

    @ObservationIgnored
    @AppStorage("transcriptDirectory") private var _transcriptDirectory: String = ""

    @ObservationIgnored
    @AppStorage("refinementEnabled") private var _refinementEnabled: Bool = false

    @ObservationIgnored
    @AppStorage("refinementProvider") private var _refinementProvider: LLMProvider = .anthropic

    @ObservationIgnored
    @AppStorage("refinementModel") private var _refinementModel: String = ""

    @ObservationIgnored
    @AppStorage("refinementPrompt") private var _refinementPrompt: String = ""

    @ObservationIgnored
    @AppStorage("appLanguage") private var _appLanguage: AppLanguage = .english

    @ObservationIgnored
    @AppStorage("hasCompletedSetup") private var _hasCompletedSetup: Bool = false


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

    var transcriptDirectory: URL {
        get {
            access(keyPath: \.transcriptDirectory)
            if _transcriptDirectory.isEmpty {
                return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            }
            return URL(fileURLWithPath: _transcriptDirectory)
        }
        set {
            withMutation(keyPath: \.transcriptDirectory) {
                _transcriptDirectory = newValue.path
            }
        }
    }

    var refinementEnabled: Bool {
        get {
            access(keyPath: \.refinementEnabled)
            return _refinementEnabled
        }
        set {
            withMutation(keyPath: \.refinementEnabled) {
                _refinementEnabled = newValue
            }
        }
    }

    var refinementProvider: LLMProvider {
        get {
            access(keyPath: \.refinementProvider)
            return _refinementProvider
        }
        set {
            withMutation(keyPath: \.refinementProvider) {
                _refinementProvider = newValue
            }
        }
    }

    var refinementModel: String {
        get {
            access(keyPath: \.refinementModel)
            let stored = _refinementModel
            return stored.isEmpty ? refinementProvider.defaultModel : stored
        }
        set {
            withMutation(keyPath: \.refinementModel) {
                _refinementModel = newValue
            }
        }
    }

    var refinementPrompt: String {
        get {
            access(keyPath: \.refinementPrompt)
            let stored = _refinementPrompt
            return stored.isEmpty ? Self.defaultRefinementPrompt : stored
        }
        set {
            withMutation(keyPath: \.refinementPrompt) {
                _refinementPrompt = newValue
            }
        }
    }

    var appLanguage: AppLanguage {
        get {
            access(keyPath: \.appLanguage)
            return _appLanguage
        }
        set {
            withMutation(keyPath: \.appLanguage) {
                _appLanguage = newValue
                L10n.current = newValue
            }
        }
    }

    var hasCompletedSetup: Bool {
        get {
            access(keyPath: \.hasCompletedSetup)
            return _hasCompletedSetup
        }
        set {
            withMutation(keyPath: \.hasCompletedSetup) {
                _hasCompletedSetup = newValue
            }
        }
    }

    var refinementAPIKey: String {
        get {
            access(keyPath: \.refinementAPIKey)
            return Self.readKeychain(service: "MacWhisperer", account: "refinementAPIKey") ?? ""
        }
        set {
            withMutation(keyPath: \.refinementAPIKey) {
                if newValue.isEmpty {
                    Self.deleteKeychain(service: "MacWhisperer", account: "refinementAPIKey")
                } else {
                    Self.writeKeychain(service: "MacWhisperer", account: "refinementAPIKey", value: newValue)
                }
            }
        }
    }

    static let defaultRefinementPrompt = """
You are a meeting transcript editor. You receive a raw transcript with speaker labels (SPEAKER_00, SPEAKER_01, etc.) and timestamps.

Your tasks:
1. Try to identify speakers by name or role from context clues in the conversation. Replace generic labels with names when confident.
2. Check if parts of sentences at speaker boundaries were attributed to the wrong speaker. Fix any misattributions.
3. Clean up obvious transcription errors while preserving the original meaning.

Return the full corrected transcript in the same Markdown format. Do not add commentary or explanations — only return the transcript.
"""

    private static func readKeychain(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    private static func writeKeychain(service: String, account: String, value: String) {
        deleteKeychain(service: service, account: account)
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func deleteKeychain(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

}
