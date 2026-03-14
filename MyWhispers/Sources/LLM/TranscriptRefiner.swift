import Foundation
import OSLog

actor TranscriptRefiner {
    static let shared = TranscriptRefiner()

    func refine(
        transcript: String,
        prompt: String,
        provider: LLMProvider,
        apiKey: String,
        model: String
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw RefinementError.missingAPIKey
        }

        let result: String
        switch provider {
        case .openAI:
            result = try await callOpenAI(transcript: transcript, prompt: prompt, apiKey: apiKey, model: model)
        case .anthropic:
            result = try await callAnthropic(transcript: transcript, prompt: prompt, apiKey: apiKey, model: model)
        }

        guard !result.isEmpty else {
            throw RefinementError.emptyResponse
        }

        return result
    }

    // MARK: - OpenAI

    private func callOpenAI(transcript: String, prompt: String, apiKey: String, model: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": transcript],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RefinementError.requestFailed("No HTTP response")
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            throw RefinementError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw RefinementError.parseError("Could not extract content from OpenAI response")
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Anthropic

    private func callAnthropic(transcript: String, prompt: String, apiKey: String, model: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8192,
            "system": prompt,
            "messages": [
                ["role": "user", "content": transcript],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RefinementError.requestFailed("No HTTP response")
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            throw RefinementError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let textBlock = content.first(where: { $0["type"] as? String == "text" }),
              let text = textBlock["text"] as? String else {
            throw RefinementError.parseError("Could not extract content from Anthropic response")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum RefinementError: LocalizedError {
    case missingAPIKey
    case emptyResponse
    case requestFailed(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "API key not configured. Set it in Settings > Meeting > AI Refinement."
        case .emptyResponse: "LLM returned an empty response."
        case .requestFailed(let detail): "LLM request failed: \(detail)"
        case .parseError(let detail): "Failed to parse LLM response: \(detail)"
        }
    }
}
