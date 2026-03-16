import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case french = "fr"
    case spanish = "es"
    case chinese = "zh"
    case portuguese = "pt"
    case german = "de"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .french: "Français"
        case .spanish: "Español"
        case .chinese: "中文"
        case .portuguese: "Português"
        case .german: "Deutsch"
        }
    }
}
