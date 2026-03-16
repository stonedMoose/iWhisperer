# Streaming WebSocket Transcription Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a streaming transcription mode that sends audio chunks over a WebSocket to Baseten's Whisper Streaming Large V3, receiving partial and final transcription results that are typed in real-time at the text cursor.

**Architecture:** A new `StreamingTranscriber` actor manages the WebSocket lifecycle — connecting to the Baseten endpoint, sending PCM audio chunks from `AudioCapture` via an `AsyncStream`, and receiving JSON transcription results. `AppState` gains a streaming recording mode that starts `AudioCapture` with a chunk callback (instead of accumulating a buffer), forwards chunks to `StreamingTranscriber`, and uses `TextInjector` to type partial results incrementally. Settings add a toggle for streaming mode, API key field, and model ID field.

**Tech Stack:** Swift, URLSessionWebSocketTask (built-in, no external dependency), AVAudioEngine (existing), CGEvent text injection (existing)

---

### Task 1: Add streaming settings to SettingsStore

**Files:**
- Modify: `MyWhispers/Sources/Settings/SettingsStore.swift`

**Step 1: Add three new `@AppStorage` properties after the `_launchAtLogin` property (after line 19)**

```swift
@ObservationIgnored
@AppStorage("streamingMode") private var _streamingMode: Bool = false

@ObservationIgnored
@AppStorage("basetenApiKey") private var _basetenApiKey: String = ""

@ObservationIgnored
@AppStorage("basetenModelId") private var _basetenModelId: String = ""
```

**Step 2: Add computed property wrappers after the `launchAtLogin` computed property (after line 84)**

```swift
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

var basetenApiKey: String {
    get {
        access(keyPath: \.basetenApiKey)
        return _basetenApiKey
    }
    set {
        withMutation(keyPath: \.basetenApiKey) {
            _basetenApiKey = newValue
        }
    }
}

var basetenModelId: String {
    get {
        access(keyPath: \.basetenModelId)
        return _basetenModelId
    }
    set {
        withMutation(keyPath: \.basetenModelId) {
            _basetenModelId = newValue
        }
    }
}
```

**Step 3: Build and verify**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add MyWhispers/Sources/Settings/SettingsStore.swift
git commit -m "feat: add streaming mode settings (toggle, API key, model ID)"
```

---

### Task 2: Add streaming settings UI to SettingsView

**Files:**
- Modify: `MyWhispers/Sources/Settings/SettingsView.swift`

**Step 1: Add a "Streaming" section after the "General" section (after the `Spacer()` on line 66, before the closing `}` of the left column VStack on line 67)**

Replace this block:

```swift
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
```

With:

```swift
                Divider()

                // Streaming
                VStack(alignment: .leading, spacing: 8) {
                    Label("Streaming", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.headline)

                    Toggle("Enable streaming mode", isOn: $settings.streamingMode)

                    if settings.streamingMode {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Baseten API Key")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            SecureField("API Key", text: $settings.basetenApiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Baseten Model ID")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Model ID", text: $settings.basetenModelId)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
```

**Step 2: Build and verify**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add MyWhispers/Sources/Settings/SettingsView.swift
git commit -m "feat: add streaming mode UI in settings (toggle, API key, model ID)"
```

---

### Task 3: Add chunk callback to AudioCapture

**Files:**
- Modify: `MyWhispers/Sources/Audio/AudioCapture.swift`

Currently `AudioCapture` accumulates all samples into `audioBuffer`. For streaming, we need it to also call a callback with each chunk of raw float samples so they can be forwarded to the WebSocket.

**Step 1: Add a callback property and a `startRecording(onChunk:)` overload**

Add after line 7 (`private let bufferLock = NSLock()`):

```swift
private var chunkCallback: (([Float]) -> Void)?
```

**Step 2: Add a new `startRecording(onChunk:)` method after the existing `startRecording()` method (after line 71)**

```swift
/// Start capturing with a per-chunk callback (for streaming).
/// Audio still accumulates in the buffer for final transcription on stop.
func startRecording(onChunk: @escaping ([Float]) -> Void) throws {
    chunkCallback = onChunk
    try startRecording()
}
```

**Step 3: In the existing tap callback, invoke the chunk callback**

In the tap closure (inside `startRecording()`), after the line `self.bufferLock.unlock()` (line 65), add:

```swift
self.chunkCallback?(samples)
```

**Step 4: In `stopRecording()`, clear the callback**

After line 76 (`engine.stop()`), add:

```swift
chunkCallback = nil
```

**Step 5: Build and verify**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 6: Commit**

```bash
git add MyWhispers/Sources/Audio/AudioCapture.swift
git commit -m "feat: add onChunk callback to AudioCapture for streaming

Audio still accumulates in the buffer for the final batch transcription,
but each chunk is also forwarded via the callback for real-time streaming."
```

---

### Task 4: Create StreamingTranscriber

**Files:**
- Create: `MyWhispers/Sources/Streaming/StreamingTranscriber.swift`

This actor manages the WebSocket connection to Baseten, sends audio chunks, and receives transcription results.

**Step 1: Create the file**

```swift
import Foundation
import OSLog

/// Manages a WebSocket connection to Baseten Whisper Streaming for real-time transcription.
actor StreamingTranscriber {
    private var webSocketTask: URLSessionWebSocketTask?
    private var onTranscript: (@MainActor (String, Bool) -> Void)?
    private let session = URLSession(configuration: .default)

    struct Config {
        let apiKey: String
        let modelId: String
        let language: String
    }

    /// Connect to the WebSocket and start receiving transcription results.
    /// `onTranscript` is called with (text, isFinal) for each result.
    func start(config: Config, onTranscript: @escaping @MainActor (String, Bool) -> Void) async throws {
        self.onTranscript = onTranscript

        let urlString = "wss://model-\(config.modelId).api.baseten.co/environments/production/websocket"
        guard let url = URL(string: urlString) else {
            throw StreamingError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.setValue("Api-Key \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        // Send initial metadata
        let metadata: [String: Any] = [
            "vad_params": [
                "threshold": 0.5,
                "min_silence_duration_ms": 300,
                "speech_pad_ms": 30
            ],
            "streaming_whisper_params": [
                "encoding": "pcm_s16le",
                "sample_rate": 16000,
                "enable_partial_transcripts": true,
                "audio_language": config.language
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: metadata)
        try await task.send(.string(String(data: jsonData, encoding: .utf8)!))

        Log.whisper.info("WebSocket connected to Baseten streaming")

        // Start receiving in background
        Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    /// Send a chunk of Float32 audio samples as PCM Int16 LE bytes.
    func sendChunk(_ samples: [Float]) async {
        guard let task = webSocketTask else { return }

        // Convert Float32 [-1,1] to Int16 PCM LE bytes
        var bytes = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * 32767)
            withUnsafeBytes(of: int16.littleEndian) { bytes.append(contentsOf: $0) }
        }

        do {
            try await task.send(.data(bytes))
        } catch {
            Log.whisper.error("WebSocket send error: \(error)")
        }
    }

    /// Stop the WebSocket connection gracefully.
    func stop() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        onTranscript = nil
        Log.whisper.info("WebSocket disconnected")
    }

    // MARK: - Private

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }

        while task.state == .running {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    parseTranscript(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        parseTranscript(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                // Connection closed or error
                if task.state != .running {
                    break
                }
                Log.whisper.error("WebSocket receive error: \(error)")
                break
            }
        }
    }

    private func parseTranscript(_ json: String) {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let transcript = dict["transcript"] as? String else {
            return
        }
        let isFinal = dict["is_final"] as? Bool ?? false
        let callback = onTranscript

        Task { @MainActor in
            callback?(transcript, isFinal)
        }
    }
}

enum StreamingError: LocalizedError {
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): "Invalid WebSocket URL: \(url)"
        }
    }
}
```

**Step 2: Build and verify**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add MyWhispers/Sources/Streaming/StreamingTranscriber.swift
git commit -m "feat: add StreamingTranscriber actor for WebSocket streaming

Manages a WebSocket connection to Baseten Whisper Streaming Large V3.
Sends PCM Int16 LE audio chunks, receives JSON transcription results
with partial and final transcript callbacks."
```

---

### Task 5: Add streaming recording mode to AppState

**Files:**
- Modify: `MyWhispers/Sources/App/AppState.swift`

This is the core integration task. AppState needs to:
- When streaming mode is ON: start AudioCapture with chunk callback, connect StreamingTranscriber, forward chunks, handle partial/final transcripts
- When streaming mode is OFF: keep current batch behavior unchanged

**Step 1: Add the streaming transcriber property**

After line 23 (`private let recordingIndicator = RecordingIndicator()`), add:

```swift
private let streamingTranscriber = StreamingTranscriber()
private var lastPartialText = ""
```

**Step 2: Replace `startRecording()` (lines 190-217)**

Replace the current `startRecording()` method with:

```swift
private func startRecording() {
    guard isModelLoaded || settingsStore.streamingMode, !isProcessing else { return }

    // Recheck permissions each time
    recheckPermissions()

    guard micPermissionGranted else {
        showPermissionError("Microphone access is required. Please grant access in System Settings > Privacy & Security > Microphone.")
        return
    }

    guard accessibilityPermissionGranted else {
        TextInjector.requestAccessibilityPermission()
        return
    }

    if settingsStore.streamingMode {
        startStreamingRecording()
    } else {
        startBatchRecording()
    }
}
```

**Step 3: Replace `stopRecordingAndTranscribe()` (lines 219-249)**

Replace the current `stopRecordingAndTranscribe()` and everything after it until the closing `}` of the class with:

```swift
private func stopRecordingAndTranscribe() async {
    guard isRecording else { return }

    if settingsStore.streamingMode {
        await stopStreamingRecording()
    } else {
        await stopBatchRecording()
    }
}

// MARK: - Batch mode

private func startBatchRecording() {
    do {
        try audioCapture.startRecording()
        guard recordingIndicator.show() else {
            _ = audioCapture.stopRecording()
            return
        }
        isRecording = true
        Log.audio.info("Recording started (batch mode)")
    } catch {
        Log.audio.error("Failed to start recording: \(error)")
    }
}

private func stopBatchRecording() async {
    let samples = audioCapture.stopRecording()
    isRecording = false
    Log.audio.info("Recording stopped, \(samples.count) samples captured")

    guard !samples.isEmpty else {
        recordingIndicator.hide()
        return
    }

    isProcessing = true
    recordingIndicator.showProcessing()

    do {
        let text = try await whisperEngine.transcribe(
            audioSamples: samples,
            language: settingsStore.selectedLanguage
        )
        Log.whisper.info("Transcription result: \(text)")
        if !text.isEmpty {
            TextInjector.typeText(text)
        }
    } catch {
        Log.whisper.error("Transcription failed: \(error)")
    }

    isProcessing = false
    recordingIndicator.hide()
}

// MARK: - Streaming mode (WebSocket)

private func startStreamingRecording() {
    guard !settingsStore.basetenApiKey.isEmpty,
          !settingsStore.basetenModelId.isEmpty else {
        showPermissionError("Please configure your Baseten API Key and Model ID in Settings to use streaming mode.")
        return
    }

    lastPartialText = ""

    do {
        try audioCapture.startRecording { [weak self] samples in
            guard let self else { return }
            Task {
                await self.streamingTranscriber.sendChunk(samples)
            }
        }
        guard recordingIndicator.show() else {
            _ = audioCapture.stopRecording()
            return
        }
        isRecording = true
        Log.audio.info("Recording started (streaming mode)")

        let language = settingsStore.selectedLanguage
        let config = StreamingTranscriber.Config(
            apiKey: settingsStore.basetenApiKey,
            modelId: settingsStore.basetenModelId,
            language: language == .auto ? "en" : language.rawValue
        )

        Task {
            do {
                try await streamingTranscriber.start(config: config) { [weak self] text, isFinal in
                    self?.handleStreamingTranscript(text: text, isFinal: isFinal)
                }
            } catch {
                Log.whisper.error("Failed to start streaming: \(error)")
            }
        }
    } catch {
        Log.audio.error("Failed to start streaming recording: \(error)")
    }
}

private func handleStreamingTranscript(text: String, isFinal: Bool) {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }

    if isFinal {
        // Delete the partial text and type the final version
        if !lastPartialText.isEmpty {
            deleteLastNCharacters(lastPartialText.count)
        }
        TextInjector.typeText(trimmed)
        lastPartialText = ""
        Log.whisper.info("Streaming final: \(trimmed)")
    } else {
        // Replace previous partial with new partial
        if !lastPartialText.isEmpty {
            deleteLastNCharacters(lastPartialText.count)
        }
        TextInjector.typeText(trimmed)
        lastPartialText = trimmed
        Log.whisper.info("Streaming partial: \(trimmed)")
    }
}

/// Delete the last N characters by simulating backspace key presses.
private func deleteLastNCharacters(_ count: Int) {
    let source = CGEventSource(stateID: .hidSystemState)
    for _ in 0..<count {
        // Virtual key 51 = delete/backspace
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        usleep(500)
    }
}

private func stopStreamingRecording() async {
    _ = audioCapture.stopRecording()
    await streamingTranscriber.stop()
    isRecording = false
    lastPartialText = ""
    recordingIndicator.hide()
    Log.audio.info("Streaming recording stopped")
}
```

**Step 4: Build and verify**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -10`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add MyWhispers/Sources/App/AppState.swift
git commit -m "feat: add streaming recording mode to AppState

When streaming mode is enabled in settings:
- AudioCapture sends chunks via callback to StreamingTranscriber
- WebSocket receives partial/final transcription results
- Partial text is typed and replaced as new partials arrive
- Final text replaces the last partial definitively
- Batch mode remains unchanged when streaming is disabled"
```

---

### Task 6: Add Log.streaming category

**Files:**
- Modify: `MyWhispers/Sources/App/Log.swift`

**Step 1: Read the file to see current log categories**

Check the existing pattern for adding a new log category.

**Step 2: Add a `streaming` log category following the existing pattern**

Add alongside the existing categories (e.g., `audio`, `whisper`, `permissions`, `general`):

```swift
static let streaming = Logger(subsystem: subsystem, category: "streaming")
```

**Step 3: Build and verify**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add MyWhispers/Sources/App/Log.swift
git commit -m "feat: add streaming log category"
```

---

### Task 7: Manual testing

**No code changes — verification only.**

**Step 1: Build the app**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build`

**Step 2: Test batch mode (baseline — should be unchanged)**

1. Ensure "Enable streaming mode" toggle is OFF in settings
2. Hold the hotkey, say "Hello world this is a test", release
3. Verify text appears at cursor
4. Confirm behavior is identical to before

**Step 3: Test streaming mode — verify settings validation**

1. Enable "Enable streaming mode" toggle
2. Leave API Key and Model ID empty
3. Try to record — should show error "Please configure your Baseten API Key and Model ID"

**Step 4: Test streaming mode — with credentials (requires Baseten account)**

1. Enter a valid Baseten API Key and Model ID
2. Hold the hotkey, speak a sentence
3. Observe: partial text should appear and update as you speak
4. On release: final text replaces last partial
5. Check Console.app for "Streaming partial:" and "Streaming final:" logs

**Step 5: Test streaming mode — connection failure**

1. Enter an invalid API Key
2. Hold the hotkey, speak
3. Verify: app doesn't crash, error is logged
4. Release — app recovers gracefully
