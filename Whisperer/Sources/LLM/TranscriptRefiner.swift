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
        if provider != .claudeCLI {
            guard !apiKey.isEmpty else {
                throw RefinementError.missingAPIKey
            }
        }

        let result: String
        switch provider {
        case .openAI:
            result = try await callOpenAI(transcript: transcript, prompt: prompt, apiKey: apiKey, model: model)
        case .anthropic:
            result = try await callAnthropic(transcript: transcript, prompt: prompt, apiKey: apiKey, model: model)
        case .claudeCLI:
            result = try await callClaudeCLI(transcript: transcript, prompt: prompt, model: model)
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

    // MARK: - Claude Code CLI

    private func callClaudeCLI(transcript: String, prompt: String, model: String) async throws -> String {
        let claudePath = Self.findClaudeBinary()
        guard let claudePath else {
            throw RefinementError.requestFailed("Claude Code CLI not found. Install it from https://claude.ai/code")
        }

        // Write transcript to a temp file to avoid shell argument limits
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("whisperer-refine-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try transcript.write(to: tempURL, atomically: true, encoding: .utf8)

        let fullPrompt = "\(prompt)\n\nHere is the transcript to refine:\n\(transcript)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = [
            "--print",
            "--model", model,
            "--prompt", fullPrompt,
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if proc.terminationStatus != 0 {
                    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                    continuation.resume(throwing: RefinementError.requestFailed("Claude CLI exited with code \(proc.terminationStatus): \(errorOutput)"))
                } else {
                    continuation.resume(returning: output)
                }
            }
        }
    }

    private static func findClaudeBinary() -> String? {
        // Check common installation paths
        let candidates = [
            "/usr/local/bin/claude",
            "\(NSHomeDirectory())/.claude/local/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fall back to `which` to find it in PATH
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["claude"]
        let pipe = Pipe()
        which.standardOutput = pipe
        do {
            try which.run()
            which.waitUntilExit()
            if which.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !path.isEmpty { return path }
            }
        } catch {}

        return nil
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
