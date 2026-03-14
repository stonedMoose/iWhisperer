# Audit Remediation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all critical and important findings from the 4-agent security/quality audit.

**Architecture:** Targeted fixes to existing files, no new architectural patterns. Each task is one isolated fix. Ordered by severity (critical first) then by dependency (upstream fixes before downstream).

**Tech Stack:** Swift 5.9+, macOS 14+, SwiftUI, AppKit, AVFoundation, whisper.cpp C bindings, Security.framework (Keychain)

---

### Task 1: Fix concurrent whisper_full crash

**Files:**
- Modify: `MyWhispers/Sources/App/AppState.swift:368-387`

**Step 1: Await streamingLoopTask completion before final batch transcription**

In `stopStreamingRecording()`, after cancelling the task, await its value before calling `whisperEngine.transcribe()`. This prevents two `whisper_full` calls racing on the same context.

Replace lines 368-374:

```swift
private func stopStreamingRecording() async {
    streamingLoopTask?.cancel()
    streamingLoopTask = nil

    let samples = audioCapture.stopRecording()
    isRecording = false
    Log.audio.info("Streaming stopped, \(samples.count) samples captured")
```

With:

```swift
private func stopStreamingRecording() async {
    streamingLoopTask?.cancel()
    await streamingLoopTask?.value  // Wait for in-flight whisper_full to finish
    streamingLoopTask = nil

    let samples = audioCapture.stopRecording()
    isRecording = false
    Log.audio.info("Streaming stopped, \(samples.count) samples captured")
```

**Step 2: Build and verify**

Run: `cd MyWhispers && swift build 2>&1 | grep -E "(error|Build complete)"`

**Step 3: Commit**

```bash
git add Sources/App/AppState.swift
git commit -m "fix: await streaming task before final transcription to prevent whisper_full race"
```

---

### Task 2: Fix AVAudioConverter input block reuse

**Files:**
- Modify: `MyWhispers/Sources/Audio/AudioCapture.swift:59-63`

**Step 1: Return noDataNow on subsequent input block invocations**

Replace:

```swift
var error: NSError?
converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
    outStatus.pointee = .haveData
    return buffer
}
```

With:

```swift
var error: NSError?
var provided = false
converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
    if !provided {
        provided = true
        outStatus.pointee = .haveData
        return buffer
    }
    outStatus.pointee = .noDataNow
    return nil
}
```

**Step 2: Build and verify**

Run: `cd MyWhispers && swift build 2>&1 | grep -E "(error|Build complete)"`

**Step 3: Commit**

```bash
git add Sources/Audio/AudioCapture.swift
git commit -m "fix: return noDataNow on subsequent AVAudioConverter input block calls"
```

---

### Task 3: Add no_speech_thold to eliminate silence hallucinations

**Files:**
- Modify: `MyWhispers/Sources/Whisper/WhisperCppEngine.swift:48-56,80-89`

**Step 1: Set no_speech_thold on both batch and streaming params**

After `params.n_threads = Int32(maxThreads)` in both `transcribe()` (line 56) and `transcribeWindow()` (line 88), add:

```swift
params.no_speech_thold = 0.6
```

Also in `transcribe()` (batch only), change the sampling strategy to beam search for better quality:

Replace line 48:
```swift
var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
```
With:
```swift
var params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
params.beam_search.beam_size = 5
```

**Step 2: Build and verify**

Run: `cd MyWhispers && swift build 2>&1 | grep -E "(error|Build complete)"`

**Step 3: Commit**

```bash
git add Sources/Whisper/WhisperCppEngine.swift
git commit -m "fix: set no_speech_thold=0.6 and use beam search for batch transcription"
```

---

### Task 4: Fix forced AXValue/AXUIElement casts

**Files:**
- Modify: `MyWhispers/Sources/UI/RecordingIndicator.swift:77,91`

**Step 1: Replace forced casts with safe casts**

Replace line 77:
```swift
let focusedElement = focused as! AXUIElement
```
With:
```swift
guard let focusedElement = focused as? AXUIElement else { return nil }
```

Replace line 91:
```swift
guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect) else { return nil }
```
With:
```swift
guard let boundsAXValue = bounds as? AXValue,
      AXValueGetValue(boundsAXValue, .cgRect, &rect) else { return nil }
```

**Step 2: Build and verify**

Run: `cd MyWhispers && swift build 2>&1 | grep -E "(error|Build complete)"`

**Step 3: Commit**

```bash
git add Sources/UI/RecordingIndicator.swift
git commit -m "fix: replace forced AXUIElement/AXValue casts with safe casts"
```

---

### Task 5: Redact transcription text from OSLog

**Files:**
- Modify: `MyWhispers/Sources/App/AppState.swift:284,358,398-399`

**Step 1: Add privacy annotation to all transcribed text logs**

Replace these lines:

```swift
Log.whisper.info("Transcription result: \(text)")
```
With:
```swift
Log.whisper.info("Transcription result: \(text, privacy: .private)")
```

```swift
Log.whisper.info("Streaming text: \(newText)")
```
With:
```swift
Log.whisper.info("Streaming text: \(newText, privacy: .private)")
```

```swift
Log.whisper.info("Streaming final: \(remainingText)")
```
With:
```swift
Log.whisper.info("Streaming final: \(remainingText, privacy: .private)")
```

```swift
Log.whisper.info("Streaming fallback: \(finalText)")
```
With:
```swift
Log.whisper.info("Streaming fallback: \(finalText, privacy: .private)")
```

**Step 2: Commit**

```bash
git add Sources/App/AppState.swift
git commit -m "fix: redact transcribed text in OSLog with privacy: .private"
```

---

### Task 6: Move HuggingFace token to Keychain

**Files:**
- Modify: `MyWhispers/Sources/Settings/SettingsStore.swift:24-25,107-117`

**Step 1: Replace AppStorage with Keychain for hfToken**

Remove the `@AppStorage("hfToken")` line (line 25) and replace the computed property:

```swift
var hfToken: String {
    get {
        access(keyPath: \.hfToken)
        return Self.readKeychain(service: "MyWhispers", account: "hfToken") ?? ""
    }
    set {
        withMutation(keyPath: \.hfToken) {
            if newValue.isEmpty {
                Self.deleteKeychain(service: "MyWhispers", account: "hfToken")
            } else {
                Self.writeKeychain(service: "MyWhispers", account: "hfToken", value: newValue)
            }
        }
    }
}

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
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecValueData as String: value.data(using: .utf8)!,
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

Also add `import Security` at the top of the file.

**Step 2: Build and verify**

Run: `cd MyWhispers && swift build 2>&1 | grep -E "(error|Build complete)"`

**Step 3: Commit**

```bash
git add Sources/Settings/SettingsStore.swift
git commit -m "fix: move HuggingFace token from UserDefaults to Keychain"
```

---

### Task 7: Pass HF token via environment variable instead of CLI arg

**Files:**
- Modify: `MyWhispers/Sources/Meeting/MeetingRecorder.swift:81-93,148-155`

**Step 1: Remove --hf_token from CLI args and pass via env**

In `transcribe(wavURL:)`, remove the `"--hf_token", hfToken,` line from `whisperXArgs` (lines 87-88).

In `runWhisperX`, after `process.standardError = errorPipe` (line 154), add:

```swift
process.environment = ProcessInfo.processInfo.environment.merging(
    ["HF_TOKEN": hfToken],
    uniquingKeysWith: { _, new in new }
)
```

This requires passing `hfToken` into `runWhisperX`. Change the signature:

```swift
private func runWhisperX(path: String, arguments: [String], hfToken: String) async throws -> (Int32, String) {
```

And update the call site (line 112):

```swift
let (exitCode, stderr) = try await runWhisperX(
    path: pythonPath,
    arguments: [scriptURL.path] + whisperXArgs,
    hfToken: hfToken
)
```

**Step 2: Build and verify**

Run: `cd MyWhispers && swift build 2>&1 | grep -E "(error|Build complete)"`

**Step 3: Commit**

```bash
git add Sources/Meeting/MeetingRecorder.swift
git commit -m "fix: pass HuggingFace token via environment variable instead of CLI arg"
```

---

### Task 8: Fix WAVWriter error handling and use async disk writes

**Files:**
- Modify: `MyWhispers/Sources/Audio/WAVWriter.swift:50-76`

**Step 1: Change queue.sync to queue.async in writeSamples**

Replace the `writeSamples` method:

```swift
func writeSamples(_ samples: [Float]) {
    let data = samples.withUnsafeBufferPointer { buffer in
        Data(bytes: buffer.baseAddress!, count: buffer.count * MemoryLayout<Float>.size)
    }
    queue.async { [self] in
        let newSize = UInt64(dataSize) + UInt64(data.count)
        guard newSize <= UInt64(UInt32.max) else {
            if dataSize < UInt32.max {
                Log.audio.warning("WAV file reached 4 GB limit, audio truncated")
            }
            return
        }
        fileHandle.write(data)
        dataSize = UInt32(newSize)
    }
}
```

**Step 2: Add defer cleanup in finalize**

Replace the `finalize` method:

```swift
func finalize() throws {
    try queue.sync {
        defer { try? fileHandle.close() }

        fileHandle.seek(toFileOffset: 40)
        var size = dataSize
        fileHandle.write(Data(bytes: &size, count: 4))

        fileHandle.seek(toFileOffset: 4)
        var riffSize = dataSize + 36
        fileHandle.write(Data(bytes: &riffSize, count: 4))
    }
}
```

Note: `queue.sync` in `finalize` ensures all pending async writes complete first (serial queue guarantees ordering).

**Step 3: Build and verify**

Run: `cd MyWhispers && swift build 2>&1 | grep -E "(error|Build complete)"`

**Step 4: Commit**

```bash
git add Sources/Audio/WAVWriter.swift
git commit -m "fix: use async disk writes in WAVWriter and add proper file handle cleanup"
```

---

### Task 9: Cap in-memory audio buffer for meeting recording

**Files:**
- Modify: `MyWhispers/Sources/Audio/AudioCapture.swift:19-23,70-71`

**Step 1: Add flag to suppress buffer accumulation**

Add a property:

```swift
private var accumulateBuffer = true
```

Add a setter method after `setOnSamples`:

```swift
func setAccumulateBuffer(_ enabled: Bool) {
    bufferLock.lock()
    accumulateBuffer = enabled
    if !enabled { audioBuffer.removeAll() }
    bufferLock.unlock()
}
```

In the tap callback (line 70-71), guard on the flag:

```swift
self.bufferLock.lock()
if self.accumulateBuffer {
    self.audioBuffer.append(contentsOf: samples)
}
let callback = self.onSamples
self.bufferLock.unlock()
callback?(samples)
```

**Step 2: Disable buffer accumulation in MeetingRecorder.startRecording**

In `MeetingRecorder.swift`, after `audioCapture.setOnSamples` (line 31), add:

```swift
audioCapture.setAccumulateBuffer(false)
```

In `MeetingRecorder.stopRecording()`, before `_ = audioCapture.stopRecording()` (line 40), add:

```swift
audioCapture.setAccumulateBuffer(true)
```

**Step 3: Build and verify**

Run: `cd MyWhispers && swift build 2>&1 | grep -E "(error|Build complete)"`

**Step 4: Commit**

```bash
git add Sources/Audio/AudioCapture.swift Sources/Meeting/MeetingRecorder.swift
git commit -m "fix: disable in-memory buffer accumulation during meeting recording"
```

---

### Task 10: Add WhisperX process timeout

**Files:**
- Modify: `MyWhispers/Sources/Meeting/MeetingRecorder.swift:112-115`

**Step 1: Wrap runWhisperX call with timeout**

Replace the `runWhisperX` call site with a timeout wrapper:

```swift
let (exitCode, stderr): (Int32, String)
do {
    (exitCode, stderr) = try await withThrowingTaskGroup(of: (Int32, String).self) { group in
        group.addTask {
            try await self.runWhisperX(
                path: pythonPath,
                arguments: [scriptURL.path] + whisperXArgs,
                hfToken: hfToken
            )
        }
        group.addTask {
            try await Task.sleep(for: .seconds(3600))
            self.transcriptionProcess?.terminate()
            throw WhisperXError.transcriptionFailed("Timed out after 1 hour")
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
} catch {
    try? FileManager.default.removeItem(at: outputDir)
    throw error
}
```

**Step 2: Build and verify**

Run: `cd MyWhispers && swift build 2>&1 | grep -E "(error|Build complete)"`

**Step 3: Commit**

```bash
git add Sources/Meeting/MeetingRecorder.swift
git commit -m "fix: add 1-hour timeout for WhisperX transcription process"
```

---

### Task 11: Clean up WAV on all error paths and temp dir on cancel

**Files:**
- Modify: `MyWhispers/Sources/Meeting/MeetingRecorder.swift:60-138,141-144`

**Step 1: Use defer to clean up WAV in transcribe()**

At the top of `transcribe(wavURL:)` after the `guard` checks (after line 71), add:

```swift
defer {
    try? FileManager.default.removeItem(at: wavURL)
}
```

Then remove the explicit `try? FileManager.default.removeItem(at: wavURL)` on line 136.

**Step 2: Store outputDir for cancel cleanup**

Add a property to MeetingRecorder:

```swift
private var currentOutputDir: URL?
```

Set it after creating the directory (after line 74):

```swift
currentOutputDir = outputDir
```

Clear it in `transcribe()`'s defer or after success.

Update `cancelTranscription()`:

```swift
func cancelTranscription() {
    transcriptionProcess?.terminate()
    transcriptionProcess = nil
    if let dir = currentOutputDir {
        try? FileManager.default.removeItem(at: dir)
        currentOutputDir = nil
    }
}
```

**Step 3: Build and verify**

Run: `cd MyWhispers && swift build 2>&1 | grep -E "(error|Build complete)"`

**Step 4: Commit**

```bash
git add Sources/Meeting/MeetingRecorder.swift
git commit -m "fix: clean up WAV on all error paths and temp dir on cancel"
```

---

### Task 12: Pin whisperx version in pip install

**Files:**
- Modify: `MyWhispers/Sources/Meeting/WhisperXInstaller.swift:35`

**Step 1: Pin the version**

Replace:

```swift
try await runProcess(pip, arguments: ["install", "whisperx"])
```

With:

```swift
try await runProcess(pip, arguments: ["install", "whisperx==3.1.6", "--no-cache-dir"])
```

**Step 2: Build and verify**

Run: `cd MyWhispers && swift build 2>&1 | grep -E "(error|Build complete)"`

**Step 3: Commit**

```bash
git add Sources/Meeting/WhisperXInstaller.swift
git commit -m "fix: pin whisperx to v3.1.6 for reproducible installs"
```

---

### Task 13: Sanitize text before CGEvent injection

**Files:**
- Modify: `MyWhispers/Sources/TextInjection/TextInjector.swift:23-39`

**Step 1: Strip control characters and cap length**

Replace `typeText`:

```swift
/// Type text at the current cursor position using CGEvent keyboard simulation.
static func typeText(_ text: String) {
    let maxLength = 5000
    let sanitized = String(text.prefix(maxLength)).unicodeScalars.filter { scalar in
        // Keep printable characters, space, newline, tab
        scalar == "\n" || scalar == "\t" || scalar == " " ||
        (scalar.properties.isAlphabetic || scalar.properties.isWhitespace ||
         scalar.properties.isEmoji || scalar.value >= 0x20 && scalar.value < 0x7F ||
         scalar.value >= 0xA0)
    }
    let cleanText = String(sanitized)

    let source = CGEventSource(stateID: .hidSystemState)

    for character in cleanText {
        let utf16 = Array(String(character).utf16)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)

        keyDown?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        keyUp?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        usleep(1000)
    }
}
```

**Step 2: Build and verify**

Run: `cd MyWhispers && swift build 2>&1 | grep -E "(error|Build complete)"`

**Step 3: Commit**

```bash
git add Sources/TextInjection/TextInjector.swift
git commit -m "fix: sanitize text before CGEvent injection — strip control chars, cap at 5000"
```

---

### Task 14: Fix getWindow() to implement keepMs overlap

**Files:**
- Modify: `MyWhispers/Sources/Audio/AudioCapture.swift:96-110`

**Step 1: Implement keepMs semantics**

The `keepMs` parameter should trim the front of the buffer, keeping only enough overlap context. Replace `getWindow`:

```swift
/// Return the last `lengthMs` of audio.
/// After returning, trims the buffer to keep only the last `keepMs` for overlap.
func getWindow(lengthMs: Int, keepMs: Int) -> [Float] {
    bufferLock.lock()
    defer { bufferLock.unlock() }

    let lengthSamples = lengthMs * 16  // 16kHz
    let keepSamples = keepMs * 16

    let maxSamples = min(audioBuffer.count, lengthSamples)
    if maxSamples <= 0 { return [] }

    let window = Array(audioBuffer.suffix(maxSamples))

    // Trim buffer to retain only keepMs overlap for next window
    let retainCount = min(audioBuffer.count, keepSamples)
    audioBuffer = Array(audioBuffer.suffix(retainCount))

    return window
}
```

**Step 2: Build and verify**

Run: `cd MyWhispers && swift build 2>&1 | grep -E "(error|Build complete)"`

**Step 3: Commit**

```bash
git add Sources/Audio/AudioCapture.swift
git commit -m "fix: implement keepMs overlap in getWindow() for proper sliding window"
```

---

### Task 15: Fix deinit crash risk in MenuBarIconState

**Files:**
- Modify: `MyWhispers/Sources/UI/MenuBarIconView.swift:96-100`

**Step 1: Replace deinit with safe timer cleanup**

Replace:

```swift
deinit {
    MainActor.assumeIsolated {
        pulseTimer?.invalidate()
    }
}
```

With:

```swift
deinit {
    // Timer holds a weak reference to self, so it will fire with nil self
    // and exit early. No explicit cleanup needed — the timer will be
    // collected when the run loop removes it after the weak self becomes nil.
    // Invalidating here is not safe because deinit may run off the main actor.
}
```

Actually, the safer approach is to store the timer reference in a way that auto-invalidates. Since the Timer uses `[weak self]` and checks `guard let self`, it will simply stop doing work when self is deallocated. The timer will eventually be collected by the run loop. Remove the deinit entirely:

Delete the `deinit` block (lines 96-100).

**Step 2: Build and verify**

Run: `cd MyWhispers && swift build 2>&1 | grep -E "(error|Build complete)"`

**Step 3: Commit**

```bash
git add Sources/UI/MenuBarIconView.swift
git commit -m "fix: remove deinit from MenuBarIconState to avoid MainActor.assumeIsolated crash"
```

---

### Task 16: Use MPS acceleration for WhisperX on Apple Silicon

**Files:**
- Modify: `MyWhispers/Sources/Meeting/MeetingRecorder.swift:84-85`

**Step 1: Detect Apple Silicon and use MPS**

Replace the hardcoded device/compute args:

```swift
"--device", "cpu",
"--compute_type", "int8",
```

With:

```swift
"--device", ProcessInfo.processInfo.machineArchitecture == "arm64" ? "mps" : "cpu",
"--compute_type", ProcessInfo.processInfo.machineArchitecture == "arm64" ? "float16" : "int8",
```

This requires a small helper. Add as an extension at the bottom of the file or inline:

```swift
private extension ProcessInfo {
    var machineArchitecture: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) ?? "unknown"
            }
        }
    }
}
```

**Step 2: Build and verify**

Run: `cd MyWhispers && swift build 2>&1 | grep -E "(error|Build complete)"`

**Step 3: Commit**

```bash
git add Sources/Meeting/MeetingRecorder.swift
git commit -m "feat: use MPS acceleration for WhisperX on Apple Silicon"
```

---

### Task 17: Cap prompt tokens to whisper context limit

**Files:**
- Modify: `MyWhispers/Sources/Whisper/WhisperCppEngine.swift:96-101`

**Step 1: Cap prompt tokens before passing to whisper_full**

In `transcribeWindow`, replace:

```swift
return promptTokens.withUnsafeBufferPointer { promptPtr in
    if !promptTokens.isEmpty {
        params.prompt_tokens = promptPtr.baseAddress
        params.prompt_n_tokens = Int32(promptPtr.count)
    }
```

With:

```swift
let maxPromptTokens = Int(whisper_n_text_ctx(ctx)) / 2
let cappedTokens = promptTokens.count > maxPromptTokens
    ? Array(promptTokens.suffix(maxPromptTokens))
    : promptTokens
return cappedTokens.withUnsafeBufferPointer { promptPtr in
    if !cappedTokens.isEmpty {
        params.prompt_tokens = promptPtr.baseAddress
        params.prompt_n_tokens = Int32(promptPtr.count)
    }
```

**Step 2: Build and verify**

Run: `cd MyWhispers && swift build 2>&1 | grep -E "(error|Build complete)"`

**Step 3: Commit**

```bash
git add Sources/Whisper/WhisperCppEngine.swift
git commit -m "fix: cap prompt tokens to whisper_n_text_ctx/2 limit"
```
