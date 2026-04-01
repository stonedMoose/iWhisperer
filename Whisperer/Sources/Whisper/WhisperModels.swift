import AppKit
import Foundation

private extension NSColor {
    /// Convenience init with 0–255 integer components (sRGB).
    convenience init(r: Int, g: Int, b: Int) {
        self.init(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
    }
}

struct FlagPattern {
    struct Band {
        let color: NSColor
        let weight: CGFloat  // relative weight; equal bands all use 1.0
    }
    enum Orientation { case horizontal, vertical }
    enum Overlay {
        /// Filled circle; cx/cy/r are normalised to [0,1] relative to the symbol rect.
        case circle(color: NSColor, cx: CGFloat, cy: CGFloat, r: CGFloat)
        /// Horizontal + vertical bars (simplified cross).
        case cross(h: NSColor, v: NSColor)
        /// Filled 5-point star; cx/cy/r normalised.
        case star(color: NSColor, cx: CGFloat, cy: CGFloat, r: CGFloat)
        /// Yin-yang circle; r normalised.
        case yinYang(top: NSColor, bottom: NSColor, r: CGFloat)
    }
    let bands: [Band]
    let orientation: Orientation
    let overlay: Overlay?
}

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

    /// Simplified flag pattern for the menu bar icon, or `nil` for auto-detect.
    var flagPattern: FlagPattern? {
        switch self {
        case .auto:
            return nil

        // ── Vertical tricolours ─────────────────────────────────────────────
        case .french:
            return FlagPattern(
                bands: [.init(color: NSColor(r:0,g:85,b:164), weight:1),
                        .init(color:.white, weight:1),
                        .init(color: NSColor(r:239,g:65,b:53), weight:1)],
                orientation: .vertical, overlay: nil)
        case .italian:
            return FlagPattern(
                bands: [.init(color: NSColor(r:0,g:146,b:70), weight:1),
                        .init(color:.white, weight:1),
                        .init(color: NSColor(r:206,g:43,b:55), weight:1)],
                orientation: .vertical, overlay: nil)

        // ── Horizontal tricolours ───────────────────────────────────────────
        case .german:
            return FlagPattern(
                bands: [.init(color: NSColor(r:0,g:0,b:0), weight:1),
                        .init(color: NSColor(r:221,g:0,b:0), weight:1),
                        .init(color: NSColor(r:255,g:206,b:0), weight:1)],
                orientation: .horizontal, overlay: nil)
        case .russian:
            return FlagPattern(
                bands: [.init(color:.white, weight:1),
                        .init(color: NSColor(r:0,g:57,b:166), weight:1),
                        .init(color: NSColor(r:213,g:43,b:30), weight:1)],
                orientation: .horizontal, overlay: nil)
        case .dutch:
            return FlagPattern(
                bands: [.init(color: NSColor(r:174,g:28,b:40), weight:1),
                        .init(color:.white, weight:1),
                        .init(color: NSColor(r:33,g:70,b:139), weight:1)],
                orientation: .horizontal, overlay: nil)
        case .arabic:
            return FlagPattern(
                bands: [.init(color: NSColor(r:0,g:0,b:0), weight:1),
                        .init(color:.white, weight:1),
                        .init(color: NSColor(r:0,g:122,b:61), weight:1)],
                orientation: .horizontal, overlay: nil)
        case .portuguese:
            return FlagPattern(
                bands: [.init(color: NSColor(r:0,g:102,b:0), weight:2),
                        .init(color: NSColor(r:255,g:0,b:0), weight:3)],
                orientation: .vertical, overlay: nil)

        // ── Spanish (wider middle band) ────────────────────────────────────
        case .spanish:
            return FlagPattern(
                bands: [.init(color: NSColor(r:196,g:30,b:58), weight:1),
                        .init(color: NSColor(r:255,g:196,b:0), weight:2),
                        .init(color: NSColor(r:196,g:30,b:58), weight:1)],
                orientation: .horizontal, overlay: nil)

        // ── English (simplified Union Jack: blue bg + cross) ───────────────
        case .english:
            return FlagPattern(
                bands: [.init(color: NSColor(r:1,g:33,b:105), weight:1)],
                orientation: .vertical,
                overlay: .cross(h: NSColor(r:200,g:16,b:46), v: NSColor(r:200,g:16,b:46)))

        // ── Japanese (white + red circle) ─────────────────────────────────
        case .japanese:
            return FlagPattern(
                bands: [.init(color:.white, weight:1)],
                orientation: .vertical,
                overlay: .circle(color: NSColor(r:188,g:0,b:45), cx:0.5, cy:0.5, r:0.28))

        // ── Chinese (red + yellow star) ────────────────────────────────────
        case .chinese:
            return FlagPattern(
                bands: [.init(color: NSColor(r:222,g:41,b:16), weight:1)],
                orientation: .vertical,
                overlay: .star(color: NSColor(r:255,g:217,b:0), cx:0.25, cy:0.72, r:0.22))

        // ── Korean (white + yin-yang) ─────────────────────────────────────
        case .korean:
            return FlagPattern(
                bands: [.init(color:.white, weight:1)],
                orientation: .vertical,
                overlay: .yinYang(top: NSColor(r:205,g:46,b:58), bottom: NSColor(r:0,g:71,b:160), r:0.28))
        }
    }
}
