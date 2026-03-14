import Foundation

enum WhisperModel: String, CaseIterable, Identifiable, Codable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"
    case largev3 = "large-v3"

    var id: String { rawValue }

    /// The GGML filename component (e.g., "large-v3" for ggml-large-v3.bin)
    var ggmlName: String { rawValue }

    /// HuggingFace download URL for the GGML model file.
    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(ggmlName).bin")!
    }

    var displayName: String {
        switch self {
        case .tiny: "Tiny (~75 MB)"
        case .base: "Base (~140 MB)"
        case .small: "Small (~460 MB)"
        case .medium: "Medium (~1.5 GB)"
        case .largev3: "Large v3 (~3 GB)"
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

enum DiarizationEngine: String, CaseIterable, Identifiable, Codable {
    case builtIn = "builtIn"
    case whisperX = "whisperX"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .builtIn: "Built-in (no account needed)"
        case .whisperX: "WhisperX (pyannote)"
        }
    }
}
