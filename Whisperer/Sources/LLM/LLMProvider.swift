import Foundation

enum LLMProvider: String, CaseIterable, Identifiable, Codable {
    case openAI = "openAI"
    case anthropic = "anthropic"
    case claudeCLI = "claudeCLI"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .claudeCLI: "Claude Code (CLI)"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: "gpt-4o"
        case .anthropic: "claude-sonnet-4-20250514"
        case .claudeCLI: "claude-sonnet-4-6-20250514"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .openAI, .anthropic: true
        case .claudeCLI: false
        }
    }
}
