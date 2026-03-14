import Foundation

enum LLMProvider: String, CaseIterable, Identifiable, Codable {
    case openAI = "openAI"
    case anthropic = "anthropic"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: "gpt-4o"
        case .anthropic: "claude-sonnet-4-20250514"
        }
    }
}
