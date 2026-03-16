# Fix Streaming Mode — Sliding Window Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the broken `AudioStreamTranscriber`-based streaming with a sliding-window approach that repeatedly batch-transcribes overlapping audio chunks, matching the proven whisper.cpp `stream` pattern.

**Architecture:** Use our existing `AudioCapture` (AVAudioEngine ring buffer) to capture audio continuously. A timer loop every `stepMs` peeks at the buffer, runs `whisperEngine.transcribe()` (full inference), and injects only text that has stabilized across two consecutive transcriptions. On stop, a final batch transcription fills in any remaining text. This eliminates dependency on WhisperKit's `AudioStreamTranscriber` entirely.

**Tech Stack:** Swift, WhisperKit (`WhisperKit.transcribe` — batch inference only), AVAudioEngine

---

### Task 1: Add peekSamples() to AudioCapture

**Files:**
- Modify: `MyWhispers/Sources/Audio/AudioCapture.swift`

Add a method to read the current audio buffer without clearing it (needed for streaming peek-while-recording), and a fast sample count accessor.

**Step 1: Add both methods after `stopRecording()` (after line 84)**

```swift
/// Return the current buffer contents without clearing (for streaming peek).
func peekSamples() -> [Float] {
    bufferLock.lock()
    let samples = audioBuffer
    bufferLock.unlock()
    return samples
}

/// Current number of captured samples (lock-free count check).
var sampleCount: Int {
    bufferLock.lock()
    let count = audioBuffer.count
    bufferLock.unlock()
    return count
}
```

**Step 2: Build and verify**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add MyWhispers/Sources/Audio/AudioCapture.swift
git commit -m "feat: add peekSamples() and sampleCount to AudioCapture

Allows reading the audio buffer without clearing it, needed for
sliding-window streaming that peeks while still recording."
```

---

### Task 2: Remove AudioStreamTranscriber from WhisperEngine

**Files:**
- Modify: `MyWhispers/Sources/Whisper/WhisperEngine.swift`

Remove the `AudioStreamTranscriber` entirely — `startStreaming()`, `stopStreaming()`, and the `streamTranscriber` property. Keep only `loadModel()` and `transcribe()`.

**Step 1: Replace the entire file with this cleaned-up version**

```swift
import Foundation
import WhisperKit

actor WhisperEngine {
    private var whisperKit: WhisperKit?
    private var currentModel: WhisperModel?

    var isLoaded: Bool { whisperKit != nil }

    /// Load (or reload) a Whisper model. Downloads from HuggingFace if not cached.
    func loadModel(_ model: WhisperModel, progressCallback: (@Sendable (Double) -> Void)? = nil) async throws {
        if currentModel == model && whisperKit != nil { return }

        whisperKit = nil
        currentModel = nil

        let modelFolder = Self.modelsDirectory
        try FileManager.default.createDirectory(atPath: modelFolder, withIntermediateDirectories: true)

        let downloadedFolder = try await WhisperKit.download(
            variant: model.rawValue,
            downloadBase: URL(fileURLWithPath: modelFolder),
            progressCallback: { progress in
                progressCallback?(progress.fractionCompleted)
            }
        )

        let config = WhisperKitConfig(
            modelFolder: downloadedFolder.path,
            download: false
        )
        whisperKit = try await WhisperKit(config)
        currentModel = model
    }

    /// Transcribe audio samples (16kHz Float array) to text.
    func transcribe(audioSamples: [Float], language: WhisperLanguage) async throws -> String {
        guard let whisperKit else {
            throw WhisperEngineError.modelNotLoaded
        }

        let options = DecodingOptions(
            language: language == .auto ? nil : language.rawValue
        )

        let results: [TranscriptionResult] = try await whisperKit.transcribe(
            audioArray: audioSamples,
            decodeOptions: options
        )

        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// ~/Library/Application Support/MyWhispers/models
    private static var modelsDirectory: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MyWhispers/models").path
    }
}

enum WhisperEngineError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: "No Whisper model is loaded."
        }
    }
}
```

**Step 2: Build and verify**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`
Expected: Build FAILS (AppState still references old streaming API). This is expected — Task 3 fixes it.

**Step 3: Commit (even though it doesn't build — the next task fixes it)**

```bash
git add MyWhispers/Sources/Whisper/WhisperEngine.swift
git commit -m "refactor: remove AudioStreamTranscriber from WhisperEngine

WhisperKit's AudioStreamTranscriber is unreliable for our use case.
The new streaming approach will use repeated batch transcribe() calls
with a sliding window, which is how whisper.cpp implements streaming."
```

---

### Task 3: Rewrite streaming mode in AppState with sliding-window approach

**Files:**
- Modify: `MyWhispers/Sources/App/AppState.swift`

This is the core task. Replace all `AudioStreamTranscriber`-based streaming code with a sliding-window approach:
- `AudioCapture` captures audio continuously (ring buffer)
- Timer loop every 3s peeks at buffer, runs batch inference
- Text that stabilizes across 2 consecutive transcriptions gets typed
- On stop, a final inference fills in remaining text

**Step 1: Remove the `import WhisperKit` line (line 5)**

Remove this line entirely — AppState no longer references `AudioStreamTranscriber.State`.

**Step 2: Replace the entire streaming section (lines 186–372)**

Remove everything from `// MARK: - Recording` (line 186) through the end of `stopStreamingRecording()` (line 372), and replace with:

```swift
    // MARK: - Recording

    private static let streamStepMs = 3000 // How often to transcribe during streaming (ms)

    private var streamingLoopTask: Task<Void, Never>?
    private var streamingTypedCount = 0
    private var lastStreamingResult = ""

    private func startRecording() {
        guard isModelLoaded, !isProcessing else { return }

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
            isRecording = true
            recordingIndicator.show()
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

    // MARK: - Streaming mode (sliding window)

    private static func cleanTranscriptionText(_ text: String) -> String {
        text.replacingOccurrences(
            of: "<\\|[^|]*\\|>",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
    }

    /// Number of leading characters that are identical in both strings.
    private static func commonPrefixCount(_ a: String, _ b: String) -> Int {
        var count = 0
        for (ca, cb) in zip(a, b) {
            if ca == cb { count += 1 } else { break }
        }
        return count
    }

    private func startStreamingRecording() {
        streamingTypedCount = 0
        lastStreamingResult = ""

        do {
            try audioCapture.startRecording()
            isRecording = true
            recordingIndicator.show()
            Log.audio.info("Recording started (streaming mode)")

            streamingLoopTask = Task {
                await streamingLoop()
            }
        } catch {
            Log.audio.error("Failed to start streaming recording: \(error)")
        }
    }

    private func streamingLoop() async {
        let minSamples = Self.streamStepMs * 16 // 16kHz = 16 samples per ms

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(Self.streamStepMs))
            guard !Task.isCancelled else { break }

            let samples = audioCapture.peekSamples()
            guard samples.count >= minSamples else { continue }

            do {
                let fullText = try await whisperEngine.transcribe(
                    audioSamples: samples,
                    language: settingsStore.selectedLanguage
                )
                guard !Task.isCancelled else { break }

                let cleanText = Self.cleanTranscriptionText(fullText)
                guard !cleanText.isEmpty else {
                    lastStreamingResult = ""
                    continue
                }

                // Text that is identical across two consecutive transcriptions is "stable"
                let stableCount = Self.commonPrefixCount(cleanText, lastStreamingResult)
                lastStreamingResult = cleanText

                // Type newly stable characters that haven't been typed yet
                if stableCount > streamingTypedCount {
                    let startIdx = cleanText.index(cleanText.startIndex, offsetBy: streamingTypedCount)
                    let endIdx = cleanText.index(cleanText.startIndex, offsetBy: stableCount)
                    let newText = String(cleanText[startIdx..<endIdx])
                    if !newText.isEmpty {
                        Log.whisper.info("Streaming text: \(newText)")
                        TextInjector.typeText(newText)
                        streamingTypedCount = stableCount
                    }
                }
            } catch {
                Log.whisper.error("Streaming transcription step failed: \(error)")
            }
        }
    }

    private func stopStreamingRecording() async {
        streamingLoopTask?.cancel()
        streamingLoopTask = nil

        let samples = audioCapture.stopRecording()
        isRecording = false
        Log.audio.info("Streaming stopped, \(samples.count) samples captured")

        guard !samples.isEmpty else {
            recordingIndicator.hide()
            return
        }

        isProcessing = true
        recordingIndicator.showProcessing()

        do {
            let fullText = try await whisperEngine.transcribe(
                audioSamples: samples,
                language: settingsStore.selectedLanguage
            )
            let cleanText = Self.cleanTranscriptionText(fullText)

            if cleanText.count > streamingTypedCount {
                let remaining = String(cleanText.dropFirst(streamingTypedCount))
                if !remaining.isEmpty {
                    Log.whisper.info("Streaming final: \(remaining)")
                    TextInjector.typeText(remaining)
                }
            } else if streamingTypedCount == 0 && !cleanText.isEmpty {
                Log.whisper.info("Streaming fallback: \(cleanText)")
                TextInjector.typeText(cleanText)
            }
        } catch {
            Log.whisper.error("Streaming final transcription failed: \(error)")
        }

        streamingTypedCount = 0
        lastStreamingResult = ""
        isProcessing = false
        recordingIndicator.hide()
        Log.audio.info("Streaming recording stopped")
    }
}
```

**Important:** The above replaces everything from `// MARK: - Recording` (line 186) through the closing `}` of the class (line 373). The file should end with the closing `}` above.

**Step 3: Build and verify**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -10`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add MyWhispers/Sources/App/AppState.swift
git commit -m "feat: rewrite streaming mode with sliding-window approach

Replace broken AudioStreamTranscriber with whisper.cpp-style streaming:
- AudioCapture acts as ring buffer, captures audio continuously
- Timer loop every 3s peeks at buffer, runs batch inference
- Text stable across 2 consecutive transcriptions gets typed
- Final batch inference on stop fills in remaining text

This uses the same proven transcribe() path as batch mode, so quality
matches. The 'streaming' effect comes from repeated inference on the
growing buffer, not from a separate streaming API."
```

---

### Task 4: Manual testing

**No code changes — just verification.**

**Step 1: Build the app**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build`

**Step 2: Test batch mode (baseline — should be unchanged)**

1. Ensure "Streaming mode" toggle is OFF in settings
2. Hold the hotkey, say "Hello world this is a test", release
3. Verify text appears at cursor
4. Note the quality

**Step 3: Test streaming mode — short recording (< 6 seconds)**

1. Enable "Streaming mode" toggle
2. Hold the hotkey, say "Hello world", release quickly
3. Verify text appears at cursor after release (final batch inference fires)
4. Check Console.app for: "Streaming fallback:" or "Streaming final:" log

**Step 4: Test streaming mode — medium recording (~10 seconds)**

1. Hold the hotkey, speak a full sentence for ~10 seconds
2. After ~6 seconds: first words should start appearing (stabilized text)
3. On release: remaining text appears
4. Check Console.app for "Streaming text:" logs during recording

**Step 5: Test streaming mode — long recording (~20+ seconds)**

1. Hold the hotkey, speak continuously for 20+ seconds
2. Text should appear incrementally every ~3-6 seconds
3. On release: final words appear
4. Quality should be comparable to batch mode
