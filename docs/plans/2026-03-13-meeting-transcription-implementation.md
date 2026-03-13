# Meeting Transcription Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add meeting recording mode with WhisperX-based transcription and speaker diarization to MyWhispers menu bar app.

**Architecture:** Toggle-based meeting recording reuses AudioCapture but streams samples to a WAV file on disk. On stop, shells out to WhisperX CLI (auto-installed in a Python venv) for transcription + diarization, parses JSON output, formats as Markdown, and presents NSSavePanel.

**Tech Stack:** Swift/SwiftUI, AVFoundation, KeyboardShortcuts, WhisperX (Python CLI), Process (Foundation)

---

### Task 1: Add `hfToken` to SettingsStore

**Files:**
- Modify: `MyWhispers/Sources/Settings/SettingsStore.swift`

**Step 1: Add the backing storage and observable property**

Add after the `_streamingMode` AppStorage (line 22):

```swift
@ObservationIgnored
@AppStorage("hfToken") private var _hfToken: String = ""
```

Add after the `streamingMode` computed property (after line 99):

```swift
var hfToken: String {
    get {
        access(keyPath: \.hfToken)
        return _hfToken
    }
    set {
        withMutation(keyPath: \.hfToken) {
            _hfToken = newValue
        }
    }
}
```

**Step 2: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add MyWhispers/Sources/Settings/SettingsStore.swift
git commit -m "feat: add hfToken setting for WhisperX diarization"
```

---

### Task 2: Add `.meetingRecord` keyboard shortcut and Meeting section to SettingsView

**Files:**
- Modify: `MyWhispers/Sources/Settings/SettingsView.swift`

**Step 1: Add the shortcut name**

Add after the `holdToRecord` extension (line 8):

```swift
static let meetingRecord = Self("meetingRecord")
```

**Step 2: Add Meeting section to left column**

Add after the Streaming section VStack (after line 78, before the `Spacer()`):

```swift
Divider()

// Meeting
VStack(alignment: .leading, spacing: 8) {
    Label("Meeting", systemImage: "person.3")
        .font(.headline)

    KeyboardShortcuts.Recorder("Meeting shortcut:", name: .meetingRecord)

    SecureField("HuggingFace Token", text: $settings.hfToken)
        .textFieldStyle(.roundedBorder)

    Link("Get a token at huggingface.co",
         destination: URL(string: "https://huggingface.co/settings/tokens")!)
        .font(.caption)
        .foregroundStyle(.secondary)

    Text("Required for speaker identification. You must also accept the pyannote speaker-diarization model terms.")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

**Step 3: Increase window height to fit new section**

Change line 111 `.frame(width: 580, height: 400)` to:

```swift
.frame(width: 580, height: 520)
```

**Step 4: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add MyWhispers/Sources/Settings/SettingsView.swift
git commit -m "feat: add meeting shortcut and HuggingFace token to settings"
```

---

### Task 3: Add `Log.meeting` category

**Files:**
- Modify: `MyWhispers/Sources/App/Log.swift`

**Step 1: Add the meeting logger**

Add after `static let ui` (line 8):

```swift
static let meeting = Logger(subsystem: "com.mywhispers.app", category: "meeting")
```

**Step 2: Commit**

```bash
git add MyWhispers/Sources/App/Log.swift
git commit -m "feat: add meeting log category"
```

---

### Task 4: Create WAVWriter

**Files:**
- Create: `MyWhispers/Sources/Audio/WAVWriter.swift`

**Step 1: Create the file**

```swift
import Foundation

final class WAVWriter {
    private let fileHandle: FileHandle
    let url: URL
    private var dataSize: UInt32 = 0
    private let sampleRate: UInt32 = 16000
    private let bitsPerSample: UInt16 = 32
    private let channels: UInt16 = 1

    init(url: URL) throws {
        self.url = url

        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        FileManager.default.createFile(atPath: url.path, contents: nil)
        self.fileHandle = try FileHandle(forWritingTo: url)
        writeHeader()
    }

    private func writeHeader() {
        var header = Data()
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)

        // RIFF header
        header.append(contentsOf: "RIFF".utf8)
        header.append(uint32: 0) // placeholder for file size - 8
        header.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        header.append(contentsOf: "fmt ".utf8)
        header.append(uint32: 16) // chunk size
        header.append(uint16: 3)  // format: IEEE float
        header.append(uint16: channels)
        header.append(uint32: sampleRate)
        header.append(uint32: byteRate)
        header.append(uint16: blockAlign)
        header.append(uint16: bitsPerSample)

        // data chunk
        header.append(contentsOf: "data".utf8)
        header.append(uint32: 0) // placeholder for data size

        fileHandle.write(header)
    }

    func writeSamples(_ samples: [Float]) {
        let data = samples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer.bindMemory(to: UInt8.self))
        }
        fileHandle.write(data)
        dataSize += UInt32(data.count)
    }

    func finalize() throws {
        // Patch data size at offset 40
        fileHandle.seek(toFileOffset: 40)
        var size = dataSize
        fileHandle.write(Data(bytes: &size, count: 4))

        // Patch RIFF size at offset 4
        fileHandle.seek(toFileOffset: 4)
        var riffSize = dataSize + 36
        fileHandle.write(Data(bytes: &riffSize, count: 4))

        fileHandle.closeFile()
    }

    func cancel() {
        fileHandle.closeFile()
        try? FileManager.default.removeItem(at: url)
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }

    mutating func append(uint32 value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}
```

**Step 2: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add MyWhispers/Sources/Audio/WAVWriter.swift
git commit -m "feat: add WAVWriter for streaming audio to disk"
```

---

### Task 5: Add sample callback to AudioCapture

**Files:**
- Modify: `MyWhispers/Sources/Audio/AudioCapture.swift`

**Step 1: Add the callback property**

Add after `private let bufferLock = NSLock()` (line 7):

```swift
private var onSamples: (([Float]) -> Void)?
```

**Step 2: Add setter method**

Add after the `requestPermission()` method (after line 16):

```swift
func setOnSamples(_ callback: (([Float]) -> Void)?) {
    bufferLock.lock()
    onSamples = callback
    bufferLock.unlock()
}
```

**Step 3: Call the callback in the tap**

Inside `startRecording()`, in the tap closure, after `self.audioBuffer.append(contentsOf: samples)` (line 64), and before `self.bufferLock.unlock()` (line 65), add:

```swift
let callback = self.onSamples
self.bufferLock.unlock()
callback?(samples)
```

And remove the existing `self.bufferLock.unlock()` on line 65 (the one right after append), since we now unlock before calling the callback.

The tap closure block (lines 58-66) should become:

```swift
if error == nil, let channelData = convertedBuffer.floatChannelData?[0] {
    let samples = Array(UnsafeBufferPointer(
        start: channelData,
        count: Int(convertedBuffer.frameLength)
    ))
    self.bufferLock.lock()
    self.audioBuffer.append(contentsOf: samples)
    let callback = self.onSamples
    self.bufferLock.unlock()
    callback?(samples)
}
```

**Step 4: Clear callback on stop**

In `stopRecording()`, after `audioBuffer.removeAll()` (line 80), add:

```swift
onSamples = nil
```

(Inside the existing lock section, before `bufferLock.unlock()`.)

**Step 5: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 6: Commit**

```bash
git add MyWhispers/Sources/Audio/AudioCapture.swift
git commit -m "feat: add onSamples callback to AudioCapture for meeting recording"
```

---

### Task 6: Create WhisperXInstaller

**Files:**
- Create: `MyWhispers/Sources/Meeting/WhisperXInstaller.swift`

**Step 1: Create the file**

```swift
import Foundation
import OSLog

actor WhisperXInstaller {
    static let shared = WhisperXInstaller()

    private var installTask: Task<Void, Error>?

    var whisperXPath: String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("MyWhispers/whisperx-env/bin/whisperx").path
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: whisperXPath)
    }

    func install(onStatus: @escaping @Sendable (String) -> Void) async throws {
        if isInstalled { return }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let envDir = support.appendingPathComponent("MyWhispers/whisperx-env")

        // Find python3
        let pythonPath = try findPython()

        onStatus("Creating Python environment...")
        try await runProcess(pythonPath, arguments: ["-m", "venv", envDir.path])

        let pip = envDir.appendingPathComponent("bin/pip").path
        onStatus("Installing WhisperX (this may take a few minutes)...")
        try await runProcess(pip, arguments: ["install", "whisperx"])

        guard isInstalled else {
            throw WhisperXError.installFailed("whisperx binary not found after installation")
        }

        Log.meeting.info("WhisperX installed successfully")
    }

    private func findPython() throws -> String {
        let candidates = ["/usr/bin/python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3"]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        // Try which
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !output.isEmpty else {
            throw WhisperXError.pythonNotFound
        }
        return output
    }

    private func runProcess(_ path: String, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardError = errorPipe

            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    continuation.resume(throwing: WhisperXError.installFailed(stderr))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum WhisperXError: LocalizedError {
    case pythonNotFound
    case installFailed(String)
    case missingHFToken
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            "Python 3 not found. Please install Python via Homebrew (brew install python) or python.org."
        case .installFailed(let detail):
            "WhisperX installation failed: \(detail)"
        case .missingHFToken:
            "HuggingFace token is required for speaker diarization. Set it in Settings > Meeting."
        case .transcriptionFailed(let detail):
            "Meeting transcription failed: \(detail)"
        }
    }
}
```

**Step 2: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add MyWhispers/Sources/Meeting/WhisperXInstaller.swift
git commit -m "feat: add WhisperXInstaller for auto-installing Python venv"
```

---

### Task 7: Create MeetingRecorder

**Files:**
- Create: `MyWhispers/Sources/Meeting/MeetingRecorder.swift`

**Step 1: Create the file**

```swift
import AppKit
import Foundation
import OSLog

@MainActor
final class MeetingRecorder {
    private let audioCapture: AudioCapture
    private let settingsStore: SettingsStore
    private var wavWriter: WAVWriter?
    private var recordingStartDate: Date?
    private var transcriptionProcess: Process?

    init(audioCapture: AudioCapture, settingsStore: SettingsStore) {
        self.audioCapture = audioCapture
        self.settingsStore = settingsStore
    }

    var isRecording: Bool { wavWriter != nil }

    func startRecording() throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "meeting-\(formatter.string(from: Date())).wav"
        let url = support.appendingPathComponent("MyWhispers/recordings/\(filename)")

        let writer = try WAVWriter(url: url)
        self.wavWriter = writer
        self.recordingStartDate = Date()

        audioCapture.setOnSamples { samples in
            writer.writeSamples(samples)
        }

        try audioCapture.startRecording()
        Log.meeting.info("Meeting recording started: \(url.lastPathComponent)")
    }

    func stopRecording() -> URL? {
        _ = audioCapture.stopRecording()

        guard let writer = wavWriter else { return nil }
        do {
            try writer.finalize()
            Log.meeting.info("Meeting WAV finalized: \(writer.url.lastPathComponent)")
        } catch {
            Log.meeting.error("Failed to finalize WAV: \(error)")
            return nil
        }

        wavWriter = nil
        return writer.url
    }

    var elapsedTime: TimeInterval {
        guard let start = recordingStartDate else { return 0 }
        return Date().timeIntervalSince(start)
    }

    func transcribe(wavURL: URL) async throws -> String {
        let installer = WhisperXInstaller.shared

        guard await installer.isInstalled else {
            throw WhisperXError.installFailed("WhisperX is not installed")
        }

        let hfToken = settingsStore.hfToken
        guard !hfToken.isEmpty else {
            throw WhisperXError.missingHFToken
        }

        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mywhispers-meeting-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let whisperXPath = await installer.whisperXPath
        let model = settingsStore.selectedModel.rawValue
        let language = settingsStore.selectedLanguage
        let langArg = language == .auto ? nil : language.rawValue

        var arguments = [
            wavURL.path,
            "--model", model,
            "--device", "cpu",
            "--compute_type", "int8",
            "--diarize",
            "--hf_token", hfToken,
            "--output_format", "json",
            "--output_dir", outputDir.path
        ]
        if let lang = langArg {
            arguments.append(contentsOf: ["--language", lang])
        }

        Log.meeting.info("Running WhisperX: \(whisperXPath)")

        let (exitCode, stderr) = try await runWhisperX(path: whisperXPath, arguments: arguments)

        guard exitCode == 0 else {
            // Clean up
            try? FileManager.default.removeItem(at: outputDir)
            throw WhisperXError.transcriptionFailed(stderr)
        }

        // Find the JSON output file
        let jsonFiles = try FileManager.default.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        guard let jsonFile = jsonFiles.first else {
            try? FileManager.default.removeItem(at: outputDir)
            throw WhisperXError.transcriptionFailed("No JSON output file found")
        }

        let jsonData = try Data(contentsOf: jsonFile)
        let markdown = try formatAsMarkdown(jsonData: jsonData, startDate: recordingStartDate ?? Date())

        // Clean up temp dir and WAV
        try? FileManager.default.removeItem(at: outputDir)
        try? FileManager.default.removeItem(at: wavURL)

        return markdown
    }

    func cancelTranscription() {
        transcriptionProcess?.terminate()
        transcriptionProcess = nil
    }

    // MARK: - Private

    private func runWhisperX(path: String, arguments: [String]) async throws -> (Int32, String) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Int32, String), Error>) in
            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardError = errorPipe
            self.transcriptionProcess = process

            process.terminationHandler = { [weak self] proc in
                let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                Task { @MainActor in
                    self?.transcriptionProcess = nil
                }
                continuation.resume(returning: (proc.terminationStatus, stderr))
            }

            do {
                try process.run()
            } catch {
                self.transcriptionProcess = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func formatAsMarkdown(jsonData: Data, startDate: Date) throws -> String {
        let result = try JSONDecoder().decode(WhisperXResult.self, from: jsonData)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dateStr = dateFormatter.string(from: startDate)

        let duration = elapsedTime
        let durationStr = formatDuration(duration)

        var md = "# Meeting Transcript\n"
        md += "**Date:** \(dateStr)\n"
        md += "**Duration:** \(durationStr)\n\n"
        md += "---\n\n"

        // Merge consecutive segments from same speaker
        var currentSpeaker: String?
        var currentText = ""
        var currentStart: Double = 0

        for segment in result.segments {
            let speaker = segment.speaker ?? "UNKNOWN"

            if speaker == currentSpeaker {
                currentText += " " + segment.text.trimmingCharacters(in: .whitespaces)
            } else {
                // Flush previous
                if let prev = currentSpeaker {
                    md += "**\(prev)** (\(formatTimestamp(currentStart)))\n"
                    md += "\(currentText.trimmingCharacters(in: .whitespaces))\n\n"
                }
                currentSpeaker = speaker
                currentText = segment.text.trimmingCharacters(in: .whitespaces)
                currentStart = segment.start
            }
        }

        // Flush last
        if let prev = currentSpeaker {
            md += "**\(prev)** (\(formatTimestamp(currentStart)))\n"
            md += "\(currentText.trimmingCharacters(in: .whitespaces))\n"
        }

        return md
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 {
            return "\(h) hour\(h > 1 ? "s" : "") \(m) min"
        }
        return "\(m) minute\(m > 1 ? "s" : "")"
    }
}

// MARK: - WhisperX JSON models

struct WhisperXResult: Codable {
    let segments: [WhisperXSegment]
}

struct WhisperXSegment: Codable {
    let start: Double
    let end: Double
    let text: String
    let speaker: String?
}
```

**Step 2: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add MyWhispers/Sources/Meeting/MeetingRecorder.swift
git commit -m "feat: add MeetingRecorder orchestrating WAV → WhisperX → Markdown"
```

---

### Task 8: Add meeting recording state and flow to AppState

**Files:**
- Modify: `MyWhispers/Sources/App/AppState.swift`

**Step 1: Add meeting state properties**

Add after `var permissionAlertMessage = ""` (line 19):

```swift
var isMeetingRecording = false
var isMeetingProcessing = false
var meetingStatusMessage = ""
var meetingElapsedTime: TimeInterval = 0
```

**Step 2: Add MeetingRecorder and timer**

Add after `private var streamingPromptTokens: [Int32] = []` (line 31):

```swift
private var meetingRecorder: MeetingRecorder?
private var meetingTimerTask: Task<Void, Never>?
```

**Step 3: Initialize MeetingRecorder in init**

In `init(settingsStore:)`, after `self.settingsStore = settingsStore` (line 38), add:

```swift
self.meetingRecorder = MeetingRecorder(audioCapture: audioCapture, settingsStore: settingsStore)
```

**Step 4: Register meeting hotkey**

In `setupHotkey()`, after the existing `onKeyUp` block (after line 171), add:

```swift
KeyboardShortcuts.onKeyDown(for: .meetingRecord) { [weak self] in
    Task { @MainActor in
        await self?.toggleMeetingRecording()
    }
}
```

**Step 5: Add conflict guard to startRecording**

In `startRecording()` (line 201), change the guard to:

```swift
guard isModelLoaded, !isProcessing, !isMeetingRecording, !isMeetingProcessing else { return }
```

**Step 6: Add meeting recording methods**

Add at the end of the class, before the closing `}`:

```swift
// MARK: - Meeting Recording

func toggleMeetingRecording() async {
    if isMeetingRecording {
        await stopMeetingAndTranscribe()
    } else {
        startMeetingRecording()
    }
}

private func startMeetingRecording() {
    guard !isRecording, !isProcessing, !isMeetingProcessing else { return }

    recheckPermissions()
    guard micPermissionGranted else {
        showPermissionError("Microphone access is required. Please grant access in System Settings > Privacy & Security > Microphone.")
        return
    }

    do {
        try meetingRecorder?.startRecording()
        isMeetingRecording = true
        meetingElapsedTime = 0
        startMeetingTimer()
        Log.meeting.info("Meeting recording started")
    } catch {
        Log.meeting.error("Failed to start meeting recording: \(error)")
    }
}

private func stopMeetingAndTranscribe() async {
    guard isMeetingRecording, let recorder = meetingRecorder else { return }

    meetingTimerTask?.cancel()
    meetingTimerTask = nil

    guard let wavURL = recorder.stopRecording() else {
        isMeetingRecording = false
        return
    }

    isMeetingRecording = false
    isMeetingProcessing = true
    meetingStatusMessage = "Checking WhisperX..."

    // Ensure WhisperX is installed
    let installer = WhisperXInstaller.shared
    if await !installer.isInstalled {
        meetingStatusMessage = "Installing WhisperX..."
        do {
            try await installer.install { [weak self] status in
                Task { @MainActor in
                    self?.meetingStatusMessage = status
                }
            }
        } catch {
            isMeetingProcessing = false
            meetingStatusMessage = ""
            showPermissionError(error.localizedDescription)
            return
        }
    }

    meetingStatusMessage = "Transcribing meeting..."

    do {
        let markdown = try await recorder.transcribe(wavURL: wavURL)
        isMeetingProcessing = false
        meetingStatusMessage = ""
        await presentSaveDialog(markdown: markdown)
    } catch {
        isMeetingProcessing = false
        meetingStatusMessage = ""
        Log.meeting.error("Meeting transcription failed: \(error)")
        showPermissionError(error.localizedDescription)
    }
}

func cancelMeetingTranscription() {
    meetingRecorder?.cancelTranscription()
    isMeetingProcessing = false
    meetingStatusMessage = ""
}

private func startMeetingTimer() {
    meetingTimerTask = Task {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { break }
            meetingElapsedTime = meetingRecorder?.elapsedTime ?? 0
        }
    }
}

private func presentSaveDialog(markdown: String) async {
    let panel = NSSavePanel()
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HHmm"
    panel.nameFieldStringValue = "Meeting-\(formatter.string(from: Date())).md"
    panel.allowedContentTypes = [.plainText]
    panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first

    let response = await panel.begin()
    if response == .OK, let url = panel.url {
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            Log.meeting.info("Meeting transcript saved to: \(url.path)")
        } catch {
            Log.meeting.error("Failed to save transcript: \(error)")
        }
    }
}
```

**Step 7: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 8: Commit**

```bash
git add MyWhispers/Sources/App/AppState.swift
git commit -m "feat: add meeting recording state and flow to AppState"
```

---

### Task 9: Update MenuBarLabel with pulsing meeting dot

**Files:**
- Modify: `MyWhispers/Sources/UI/MenuBarLabel.swift`

**Step 1: Add meeting state and pulsing animation**

Replace the entire file content with:

```swift
import SwiftUI

struct MenuBarLabel: View {
    let isRecording: Bool
    let isProcessing: Bool
    let isMeetingRecording: Bool
    let isMeetingProcessing: Bool

    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        Image("MenuBarIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)
            .overlay(alignment: .bottomTrailing) {
                if isMeetingRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                        .offset(x: 2, y: 2)
                        .opacity(pulseOpacity)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                pulseOpacity = 0.3
                            }
                        }
                        .onDisappear {
                            pulseOpacity = 1.0
                        }
                } else if isRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                        .offset(x: 2, y: 2)
                } else if isProcessing || isMeetingProcessing {
                    Circle()
                        .fill(.orange)
                        .frame(width: 7, height: 7)
                        .offset(x: 2, y: 2)
                }
            }
    }
}
```

**Step 2: Build — this will fail because callers need updating**

Expected: Build fails with missing arguments at call sites. We'll fix in the next task.

**Step 3: Commit**

```bash
git add MyWhispers/Sources/UI/MenuBarLabel.swift
git commit -m "feat: add pulsing meeting recording dot to MenuBarLabel"
```

---

### Task 10: Update MyWhispersApp menu bar with meeting controls

**Files:**
- Modify: `MyWhispers/Sources/App/MyWhispersApp.swift`

**Step 1: Update MenuBarExtra label**

The current `MenuBarExtra` uses `systemImage: "waveform"` (line 17). This needs to change to use our custom `MenuBarLabel`. However, since `MenuBarExtra` with `.menu` style uses the label directly, and SwiftUI menu bar extras with menu style only support text/image labels, we keep the systemImage but add the meeting status to the menu content.

Actually, looking at the code, the label isn't using `MenuBarLabel` at all currently — it uses `systemImage`. Let's keep that as is for now and focus on the menu content.

**Step 2: Add meeting status to the status section**

In the status section, after `} else if appState.isRecording {` block (line 35), add meeting states. Replace the entire status section (lines 19-42) with:

```swift
// Status
if !appState.micPermissionGranted {
    Label("Microphone not authorized", systemImage: "exclamationmark.triangle")
    Button("Open Microphone Settings...") {
        appState.openMicrophoneSettings()
    }
} else if !appState.accessibilityPermissionGranted {
    Label("Accessibility not authorized", systemImage: "exclamationmark.triangle")
    Button("Open Accessibility Settings...") {
        appState.openAccessibilitySettings()
    }
    Button("Restart App (required after granting)") {
        appState.relaunch()
    }
} else if appState.isMeetingProcessing {
    Text(appState.meetingStatusMessage.isEmpty ? "Processing meeting..." : appState.meetingStatusMessage)
} else if appState.isMeetingRecording {
    let elapsed = Int(appState.meetingElapsedTime)
    let m = elapsed / 60
    let s = elapsed % 60
    Text("Recording meeting \(String(format: "%d:%02d", m, s))")
} else if appState.isProcessing {
    Text("Transcribing...")
} else if appState.isRecording {
    Text("Recording...")
} else if appState.isDownloadingModel {
    Text("Downloading model - \(appState.downloadingModelName) - \(Int(appState.downloadProgress * 100))%")
} else if !appState.isModelLoaded {
    Text("Loading model...")
} else {
    Text("Ready")
}
```

**Step 3: Add meeting controls section**

After the Language section Divider (after line 68), add:

```swift
// Meeting
Section("Meeting") {
    if appState.isMeetingRecording {
        Button("Stop Meeting Recording") {
            Task {
                await appState.toggleMeetingRecording()
            }
        }
    } else if appState.isMeetingProcessing {
        Text("Transcribing meeting...")
        Button("Cancel Transcription") {
            appState.cancelMeetingTranscription()
        }
    } else {
        Button("Start Meeting Recording") {
            Task {
                await appState.toggleMeetingRecording()
            }
        }
        .disabled(!appState.isModelLoaded || appState.isRecording || appState.isProcessing)
    }
}

Divider()
```

**Step 4: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add MyWhispers/Sources/App/MyWhispersApp.swift
git commit -m "feat: add meeting recording controls to menu bar"
```

---

### Task 11: Integration test — manual build and verify

**Step 1: Full build**

Run: `swift build 2>&1 | tail -20`
Expected: Build succeeds with no errors

**Step 2: Fix any remaining compilation issues**

Address any type mismatches, missing imports, or call-site issues that arise from the changes across tasks 1-10.

**Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve compilation issues from meeting feature integration"
```

---

### Task 12: Clean up unused MenuBarLabel parameters (if needed)

If `MenuBarLabel` is not currently used anywhere (the app uses `systemImage: "waveform"`), the new parameters won't cause build errors. But if it IS used somewhere we missed, update the call site to pass the new `isMeetingRecording` and `isMeetingProcessing` parameters.

**Step 1: Search for MenuBarLabel usage**

Run: `grep -rn "MenuBarLabel" MyWhispers/Sources/`

**Step 2: Update any call sites found**

Add `isMeetingRecording: appState.isMeetingRecording` and `isMeetingProcessing: appState.isMeetingProcessing` to each call site.

**Step 3: Build and commit**

```bash
swift build 2>&1 | tail -5
git add -A
git commit -m "fix: update MenuBarLabel call sites with meeting state"
```
