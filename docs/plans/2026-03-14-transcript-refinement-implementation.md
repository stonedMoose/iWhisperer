# LLM Transcript Refinement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add optional LLM-based refinement of meeting transcripts using OpenAI or Anthropic APIs.

**Architecture:** New `TranscriptRefiner` actor handles HTTP calls to LLM providers. Settings store refinement preferences (toggle, provider, API key in Keychain, model name, prompt). After diarization produces a transcript, AppState optionally sends it through refinement before saving.

**Tech Stack:** Swift, URLSession, Security framework (Keychain), SwiftUI

---

### Task 1: Add LLMProvider Enum and Refinement Settings

**Files:**
- Create: `Sources/LLM/LLMProvider.swift`
- Modify: `Sources/Settings/SettingsStore.swift`

**Step 1: Create LLMProvider enum**

Create `Sources/LLM/LLMProvider.swift`:

```swift
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
```

**Step 2: Add refinement settings to SettingsStore**

In `Sources/Settings/SettingsStore.swift`, add `import Security` at the top, then add these @AppStorage properties after `_transcriptDirectory` (line 25):

```swift
@ObservationIgnored
@AppStorage("refinementEnabled") private var _refinementEnabled: Bool = false

@ObservationIgnored
@AppStorage("refinementProvider") private var _refinementProvider: LLMProvider = .anthropic

@ObservationIgnored
@AppStorage("refinementModel") private var _refinementModel: String = ""

@ObservationIgnored
@AppStorage("refinementPrompt") private var _refinementPrompt: String = ""
```

Add computed properties after `transcriptDirectory` (after line 118):

```swift
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

var refinementAPIKey: String {
    get {
        access(keyPath: \.refinementAPIKey)
        return Self.readKeychain(service: "MyWhispers", account: "refinementAPIKey") ?? ""
    }
    set {
        withMutation(keyPath: \.refinementAPIKey) {
            if newValue.isEmpty {
                Self.deleteKeychain(service: "MyWhispers", account: "refinementAPIKey")
            } else {
                Self.writeKeychain(service: "MyWhispers", account: "refinementAPIKey", value: newValue)
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
```

Add Keychain helpers at the bottom of the class (before the closing `}`):

```swift
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
```

**Step 3: Verify it compiles**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`

**Step 4: Commit**

```bash
git add Sources/LLM/LLMProvider.swift Sources/Settings/SettingsStore.swift
git commit -m "feat: add LLMProvider enum and refinement settings"
```

---

### Task 2: Update Settings UI

**Files:**
- Modify: `Sources/Settings/SettingsView.swift`

**Step 1: Add refinement section to Meeting column**

In `Sources/Settings/SettingsView.swift`, in Column 4 (Meeting), add a new section after the "Transcript Location" section (after line 175, before the `Spacer()`):

```swift
Divider()

VStack(alignment: .leading, spacing: 8) {
    Label("AI Refinement", systemImage: "sparkles")
        .font(.headline)

    Toggle("Refine transcript with AI", isOn: $settings.refinementEnabled)

    if settings.refinementEnabled {
        Picker("Provider", selection: $settings.refinementProvider) {
            ForEach(LLMProvider.allCases) { provider in
                Text(provider.displayName).tag(provider)
            }
        }
        .onChange(of: settings.refinementProvider) { _, newValue in
            settings.refinementModel = newValue.defaultModel
        }

        SecureField("API Key", text: $settings.refinementAPIKey)
            .textFieldStyle(.roundedBorder)

        TextField("Model", text: $settings.refinementModel)
            .textFieldStyle(.roundedBorder)

        Text("Prompt:")
            .font(.caption)
            .foregroundStyle(.secondary)

        TextEditor(text: $settings.refinementPrompt)
            .font(.caption)
            .frame(height: 80)
            .border(Color.secondary.opacity(0.3))

        Button("Reset prompt to default") {
            settings.refinementPrompt = SettingsStore.defaultRefinementPrompt
        }
        .font(.caption)
    }
}
```

The settings window may need more height. Update the frame at line 182:

```swift
.frame(width: 920, height: settings.refinementEnabled ? 680 : 480)
```

Note: Access `settings` (the `@Environment` one) for the height check. Use `@Bindable var settings` which is already declared at line 15.

**Step 2: Verify it compiles**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`

**Step 3: Commit**

```bash
git add Sources/Settings/SettingsView.swift
git commit -m "feat: add AI refinement section to settings UI"
```

---

### Task 3: Create TranscriptRefiner

**Files:**
- Create: `Sources/LLM/TranscriptRefiner.swift`

**Step 1: Create the refiner actor**

Create `Sources/LLM/TranscriptRefiner.swift`:

```swift
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
```

**Step 2: Verify it compiles**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`

**Step 3: Commit**

```bash
git add Sources/LLM/TranscriptRefiner.swift
git commit -m "feat: add TranscriptRefiner with OpenAI and Anthropic support"
```

---

### Task 4: Wire Refinement into Meeting Flow

**Files:**
- Modify: `Sources/App/AppState.swift`

**Step 1: Add refinement step after transcription**

In `Sources/App/AppState.swift`, find the `stopMeetingAndTranscribe` method. Replace the transcription `do` block (lines 469-483) with:

```swift
do {
    meetingStatusMessage = "Preparing models..."
    _ = try await ModelManager.shared.ensureDiarizationModel(.segmentation)
    _ = try await ModelManager.shared.ensureDiarizationModel(.embedding)
    meetingStatusMessage = "Transcribing & identifying speakers..."
    var markdown = try await recorder.transcribe(wavURL: wavURL)

    // Optional LLM refinement
    if settingsStore.refinementEnabled {
        meetingStatusMessage = "Refining transcript..."
        do {
            markdown = try await TranscriptRefiner.shared.refine(
                transcript: markdown,
                prompt: settingsStore.refinementPrompt,
                provider: settingsStore.refinementProvider,
                apiKey: settingsStore.refinementAPIKey,
                model: settingsStore.refinementModel
            )
        } catch {
            Log.meeting.error("Transcript refinement failed, saving raw transcript: \(error)")
        }
    }

    isMeetingProcessing = false
    meetingStatusMessage = ""
    saveTranscript(markdown: markdown)
} catch {
    isMeetingProcessing = false
    meetingStatusMessage = ""
    Log.meeting.error("Meeting transcription failed: \(error)")
    showPermissionError(error.localizedDescription)
}
```

Key: if refinement fails, the raw transcript is still saved (the `catch` inside only logs, doesn't rethrow).

**Step 2: Verify it compiles**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`

**Step 3: Commit**

```bash
git add Sources/App/AppState.swift
git commit -m "feat: wire LLM transcript refinement into meeting flow"
```

---

### Task 5: End-to-End Testing

**Step 1: Build and run**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build && swift run`

**Step 2: Test with refinement disabled (default)**

1. Open Settings — verify Meeting column has "AI Refinement" section with toggle off
2. Verify no provider/key/model/prompt fields visible
3. Record and transcribe a meeting — should work exactly as before

**Step 3: Test with refinement enabled**

1. Toggle "Refine transcript with AI" on
2. Verify provider picker, API key, model, and prompt fields appear
3. Select a provider, enter API key, verify model default populates
4. Record a short meeting, stop, verify status shows "Refining transcript..."
5. Verify refined transcript is saved

**Step 4: Test error handling**

1. Enable refinement with an invalid API key
2. Record and transcribe — verify raw transcript is saved despite refinement failure

**Step 5: Test prompt customization**

1. Edit the prompt in settings
2. Verify custom prompt is used
3. Click "Reset prompt to default" — verify it resets

**Step 6: Commit any fixes**

```bash
git add -A
git commit -m "fix: adjustments from end-to-end testing"
```
