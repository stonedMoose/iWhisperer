import Foundation

enum WhisperModel: String, CaseIterable, Identifiable, Codable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"

    var id: String { rawValue }
    var ggmlName: String { rawValue }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(ggmlName).bin")!
    }

    var displayName: String {
        switch self {
        case .tiny: "Tiny (~75 MB)"
        case .base: "Base (~142 MB)"
        case .small: "Small (~466 MB)"
        }
    }

    var sizeBytes: Int64 {
        switch self {
        case .tiny: 75_000_000
        case .base: 142_000_000
        case .small: 466_000_000
        }
    }
}

enum WhisperLanguage: String, CaseIterable, Identifiable, Codable {
    case auto = "auto"
    case english = "en"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case italian = "it"
    case portuguese = "pt"
    case dutch = "nl"
    case japanese = "ja"
    case chinese = "zh"
    case korean = "ko"
    case russian = "ru"
    case arabic = "ar"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: "Auto-detect"
        case .english: "English"
        case .french: "French"
        case .german: "German"
        case .spanish: "Spanish"
        case .italian: "Italian"
        case .portuguese: "Portuguese"
        case .dutch: "Dutch"
        case .japanese: "Japanese"
        case .chinese: "Chinese"
        case .korean: "Korean"
        case .russian: "Russian"
        case .arabic: "Arabic"
        }
    }
}
