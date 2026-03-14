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

    var hfToken: String {
        get {
            access(keyPath: \.hfToken)
            return Self.readKeychain(service: "MyWhispers", account: "hfToken") ?? ""
        }
        set {
            withMutation(keyPath: \.hfToken) {
                if newValue.isEmpty {
                    Self.deleteKeychain(service: "MyWhispers", account: "hfToken")
                } else {
                    Self.writeKeychain(service: "MyWhispers", account: "hfToken", value: newValue)
                }
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
