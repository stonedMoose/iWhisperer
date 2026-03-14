# MyWhispers iOS Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an iOS app for quick voice-to-text dictation using local whisper.cpp, triggered via Action Button, with Live Activity status and transcription history.

**Architecture:** Single-target iOS app (SwiftUI, iOS 17+, iPhone 15 Pro+). Uses an Xcode project (not SPM executable) with whisper.cpp compiled as static libraries for arm64-ios. Core engine code ported from macOS app at `MyWhispers/Sources/`. TranscriptionEngine is the central @Observable state machine coordinating AudioCapture → WhisperCppEngine → clipboard/history.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData, ActivityKit (Live Activities), AppIntents (Action Button), AVAudioEngine, whisper.cpp (C interop via static libs + Metal)

**Reference:** Design doc at `docs/plans/2026-03-14-mywhispers-ios-design.md`, macOS source at `MyWhispers/Sources/`

---

## Task 0: Cross-compile whisper.cpp for iOS

This task builds the whisper.cpp static libraries for arm64 iOS. The macOS app uses prebuilt `.a` files at `MyWhispers/Vendor/whisper-built/lib/`. We need the equivalent for iOS.

**Files:**
- Create: `MyWhispersIOS/Scripts/build-whisper-ios.sh`

**Step 1: Create the build script**

```bash
#!/bin/bash
set -euo pipefail

# Build whisper.cpp static libraries for iOS arm64
# Requires: CMake, Xcode command line tools

WHISPER_SRC="$(cd "$(dirname "$0")/../../MyWhispers/Vendor/whisper.cpp" && pwd)"
OUTPUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/Vendor/whisper-built"
BUILD_DIR="/tmp/whisper-ios-build"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR/lib" "$OUTPUT_DIR/include"

cd "$BUILD_DIR"

cmake "$WHISPER_SRC" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DCMAKE_INSTALL_PREFIX="$OUTPUT_DIR" \
  -DWHISPER_METAL=ON \
  -DWHISPER_COREML=OFF \
  -DWHISPER_NO_METAL_EMBED_LIBRARY=OFF \
  -DBUILD_SHARED_LIBS=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_EXAMPLES=OFF

cmake --build . --config Release -j$(sysctl -n hw.ncpu)

# Copy libraries
find . -name "*.a" -exec cp {} "$OUTPUT_DIR/lib/" \;

# Copy headers
cp "$WHISPER_SRC/include/whisper.h" "$OUTPUT_DIR/include/"
cp "$WHISPER_SRC/ggml/include/ggml.h" "$OUTPUT_DIR/include/"
cp "$WHISPER_SRC/ggml/include/ggml-alloc.h" "$OUTPUT_DIR/include/"
cp "$WHISPER_SRC/ggml/include/ggml-backend.h" "$OUTPUT_DIR/include/"
cp "$WHISPER_SRC/ggml/include/ggml-metal.h" "$OUTPUT_DIR/include/"
cp "$WHISPER_SRC/ggml/include/ggml-cpu.h" "$OUTPUT_DIR/include/"
cp "$WHISPER_SRC/ggml/include/ggml-cpp.h" "$OUTPUT_DIR/include/"
cp "$WHISPER_SRC/ggml/include/ggml-opt.h" "$OUTPUT_DIR/include/"
cp "$WHISPER_SRC/ggml/include/gguf.h" "$OUTPUT_DIR/include/"

echo "✅ whisper.cpp built for iOS arm64 at $OUTPUT_DIR"
ls -la "$OUTPUT_DIR/lib/"
```

**Step 2: Run the build script**

```bash
chmod +x MyWhispersIOS/Scripts/build-whisper-ios.sh
./MyWhispersIOS/Scripts/build-whisper-ios.sh
```

Expected: Static `.a` files in `MyWhispersIOS/Vendor/whisper-built/lib/` and headers in `include/`.

**Step 3: Verify the libraries are arm64 iOS**

```bash
lipo -info MyWhispersIOS/Vendor/whisper-built/lib/libwhisper.a
```

Expected: `Non-fat file: ... is architecture: arm64`

**Step 4: Commit**

```bash
git add MyWhispersIOS/Scripts/build-whisper-ios.sh
git commit -m "build: add whisper.cpp cross-compile script for iOS arm64"
```

> **Note:** The built `.a` files and headers should be gitignored. Add `MyWhispersIOS/Vendor/whisper-built/` to `.gitignore`.

---

## Task 1: Xcode project scaffold

Create the iOS Xcode project with the correct structure, C library bridging, and build settings.

**Files:**
- Create: `MyWhispersIOS/` directory structure
- Create: `MyWhispersIOS/MyWhispersIOS.xcodeproj` (via Xcode or `xcodegen`)
- Create: `MyWhispersIOS/Vendor/CWhisper/module.modulemap`
- Create: `MyWhispersIOS/Vendor/CWhisper/shim.h`
- Create: `MyWhispersIOS/Sources/App/MyWhispersIOSApp.swift`

**Step 1: Create directory structure**

```bash
mkdir -p MyWhispersIOS/Sources/{App,Audio,Whisper,Intents,LiveActivity,History,Settings}
mkdir -p MyWhispersIOS/Vendor/CWhisper
mkdir -p MyWhispersIOS/Resources/Assets.xcassets
mkdir -p MyWhispersIOS/MyWhispersIOSWidgetExtension
```

**Step 2: Create the C module map for whisper.cpp**

Create `MyWhispersIOS/Vendor/CWhisper/module.modulemap`:

```
module CWhisper {
    header "shim.h"
    link "whisper"
    link "ggml"
    link "ggml-base"
    link "ggml-cpu"
    link "ggml-metal"
    export *
}
```

Create `MyWhispersIOS/Vendor/CWhisper/shim.h`:

```c
#ifndef CWHISPER_SHIM_H
#define CWHISPER_SHIM_H

#include "whisper.h"

#endif
```

**Step 3: Create minimal app entry point**

Create `MyWhispersIOS/Sources/App/MyWhispersIOSApp.swift`:

```swift
import SwiftUI
import SwiftData

@main
struct MyWhispersIOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Transcription.self)
    }
}

struct ContentView: View {
    var body: some View {
        NavigationStack {
            Text("MyWhispers")
                .navigationTitle("MyWhispers")
        }
    }
}
```

**Step 4: Create Xcode project**

Use Xcode to create a new iOS App project at `MyWhispersIOS/`:
- Product name: MyWhispersIOS
- Bundle ID: `com.julienlhermite.MyWhispersIOS`
- Deployment target: iOS 17.0
- Add the following to Build Settings:
  - `SWIFT_INCLUDE_PATHS` = `$(PROJECT_DIR)/Vendor/CWhisper`
  - `HEADER_SEARCH_PATHS` = `$(PROJECT_DIR)/Vendor/whisper-built/include`
  - `LIBRARY_SEARCH_PATHS` = `$(PROJECT_DIR)/Vendor/whisper-built/lib`
  - `OTHER_LDFLAGS` = `-lwhisper -lggml -lggml-base -lggml-cpu -lggml-metal -lc++`
  - Link frameworks: `Metal`, `MetalKit`, `Accelerate`, `AVFoundation`
- Add capability: `Background Modes` → Audio
- Add `NSMicrophoneUsageDescription` to Info.plist

**Step 5: Build to verify the project compiles**

```bash
xcodebuild -project MyWhispersIOS/MyWhispersIOS.xcodeproj -scheme MyWhispersIOS -sdk iphoneos -configuration Debug build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

**Step 6: Commit**

```bash
git add MyWhispersIOS/
git commit -m "feat(ios): scaffold Xcode project with whisper.cpp C bridging"
```

---

## Task 2: SwiftData model + history

**Files:**
- Create: `MyWhispersIOS/Sources/History/Transcription.swift`
- Create: `MyWhispersIOS/Sources/History/HistoryView.swift`

**Step 1: Create the SwiftData model**

Create `MyWhispersIOS/Sources/History/Transcription.swift`:

```swift
import Foundation
import SwiftData

@Model
final class Transcription {
    var text: String
    var language: String
    var model: String
    var duration: TimeInterval
    var createdAt: Date

    init(text: String, language: String, model: String, duration: TimeInterval) {
        self.text = text
        self.language = language
        self.model = model
        self.duration = duration
        self.createdAt = Date()
    }
}
```

**Step 2: Create the history list view**

Create `MyWhispersIOS/Sources/History/HistoryView.swift`:

```swift
import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \Transcription.createdAt, order: .reverse)
    private var transcriptions: [Transcription]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            if transcriptions.isEmpty {
                ContentUnavailableView(
                    "No Transcriptions",
                    systemImage: "waveform",
                    description: Text("Press the Action Button to start dictating")
                )
            } else {
                ForEach(transcriptions) { transcription in
                    TranscriptionRow(transcription: transcription)
                }
                .onDelete(perform: delete)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(transcriptions[index])
        }
    }
}

struct TranscriptionRow: View {
    let transcription: Transcription

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(transcription.text)
                .lineLimit(2)
                .font(.body)

            HStack {
                Text(transcription.createdAt, style: .relative)
                Text("·")
                Text(formatDuration(transcription.duration))
                Text("·")
                Text(transcription.language)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = transcription.text
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m \(s % 60)s"
    }
}
```

**Step 3: Wire into ContentView**

Update `MyWhispersIOSApp.swift` ContentView:

```swift
struct ContentView: View {
    var body: some View {
        NavigationStack {
            HistoryView()
                .navigationTitle("MyWhispers")
        }
    }
}
```

**Step 4: Build and verify**

```bash
xcodebuild -project MyWhispersIOS/MyWhispersIOS.xcodeproj -scheme MyWhispersIOS -sdk iphoneos build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

**Step 5: Commit**

```bash
git add MyWhispersIOS/Sources/History/
git commit -m "feat(ios): add SwiftData Transcription model and history view"
```

---

## Task 3: Whisper engine + model management (port from macOS)

Port `WhisperCppEngine`, `ModelManager`, and `WhisperModels` from macOS, adapting for iOS (no `Process` class, iOS file paths, reduced model list).

**Files:**
- Create: `MyWhispersIOS/Sources/Whisper/WhisperCppEngine.swift`
- Create: `MyWhispersIOS/Sources/Whisper/ModelManager.swift`
- Create: `MyWhispersIOS/Sources/Whisper/WhisperModels.swift`
- Create: `MyWhispersIOS/Sources/App/Log.swift`
- Reference: `MyWhispers/Sources/Whisper/WhisperCppEngine.swift`

**Step 1: Create Log utility**

Create `MyWhispersIOS/Sources/App/Log.swift`:

```swift
import OSLog

enum Log {
    static let whisper = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MyWhispersIOS", category: "whisper")
    static let audio = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MyWhispersIOS", category: "audio")
    static let app = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MyWhispersIOS", category: "app")
}
```

**Step 2: Create WhisperModels (reduced for iOS)**

Create `MyWhispersIOS/Sources/Whisper/WhisperModels.swift`:

```swift
import Foundation

enum WhisperModel: String, CaseIterable, Identifiable, Codable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"

    var id: String { rawValue }

    var ggmlName: String { rawValue }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(ggmlName).bin")!
    }

    var displayName: String {
        switch self {
        case .tiny: "Tiny (~75 MB)"
        case .base: "Base (~142 MB)"
        case .small: "Small (~466 MB)"
        }
    }

    var sizeBytes: Int64 {
        switch self {
        case .tiny: 75_000_000
        case .base: 142_000_000
        case .small: 466_000_000
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
}
```

**Step 3: Create WhisperCppEngine (ported from macOS)**

Create `MyWhispersIOS/Sources/Whisper/WhisperCppEngine.swift`:

```swift
import CWhisper
import Foundation

actor WhisperCppEngine {
    private var ctx: OpaquePointer?

    var isLoaded: Bool { ctx != nil }

    func loadModel(path: String) throws {
        unloadModel()

        var params = whisper_context_default_params()
        params.use_gpu = true
        params.flash_attn = true

        guard let context = whisper_init_from_file_with_params(path, params) else {
            throw WhisperError.modelLoadFailed(path)
        }

        ctx = context
        Log.whisper.info("Model loaded: \(path)")
    }

    func unloadModel() {
        if let ctx { whisper_free(ctx) }
        ctx = nil
    }

    deinit {
        if let ctx { whisper_free(ctx) }
    }

    func transcribe(samples: [Float], language: String) -> String {
        guard let ctx else { return "" }

        let maxThreads = max(1, min(4, ProcessInfo.processInfo.processorCount - 1))
        var params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
        params.beam_search.beam_size = 5
        params.print_realtime = false
        params.print_progress = false
        params.print_special = false
        params.print_timestamps = false
        params.translate = false
        params.single_segment = false
        params.no_context = true
        params.n_threads = Int32(maxThreads)
        params.no_speech_thold = 0.6

        let lang = language == "auto" ? nil : language
        let result: Int32 = lang.withOptionalCString { langPtr in
            params.language = langPtr
            return samples.withUnsafeBufferPointer { samplesPtr in
                whisper_full(ctx, params, samplesPtr.baseAddress, Int32(samplesPtr.count))
            }
        }

        guard result == 0 else {
            Log.whisper.error("whisper_full failed: \(result)")
            return ""
        }

        return collectSegmentText()
    }

    private func collectSegmentText() -> String {
        guard let ctx else { return "" }
        var text = ""
        let nSegments = whisper_full_n_segments(ctx)
        for i in 0..<nSegments {
            if let cStr = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: cStr)
            }
        }
        return cleanText(text)
    }

    private func cleanText(_ text: String) -> String {
        text.replacingOccurrences(
            of: "<\\|[^|]*\\|>",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
    }
}

private extension Optional where Wrapped == String {
    func withOptionalCString<R>(_ body: (UnsafePointer<CChar>?) -> R) -> R {
        switch self {
        case .some(let string): string.withCString { body($0) }
        case .none: body(nil)
        }
    }
}

enum WhisperError: LocalizedError {
    case modelLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path): "Failed to load whisper model at: \(path)"
        }
    }
}
```

**Step 4: Create ModelManager (adapted for iOS — no Process, uses Documents dir)**

Create `MyWhispersIOS/Sources/Whisper/ModelManager.swift`:

```swift
import Foundation

actor ModelManager {
    static let shared = ModelManager()

    func ensureModel(_ model: WhisperModel, progress: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        let path = modelPath(for: model)

        if FileManager.default.fileExists(atPath: path) {
            Log.whisper.info("Model cached: \(path)")
            progress?(1.0)
            return path
        }

        let dir = modelsDirectory
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        Log.whisper.info("Downloading \(model.rawValue)...")

        let delegate = DownloadDelegate(progressCallback: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (tempURL, response) = try await session.download(from: model.downloadURL, delegate: delegate)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ModelManagerError.downloadFailed(model.rawValue)
        }

        try FileManager.default.moveItem(atPath: tempURL.path, toPath: path)
        Log.whisper.info("Model saved: \(path)")
        return path
    }

    func modelPath(for model: WhisperModel) -> String {
        modelsDirectory + "/ggml-\(model.ggmlName).bin"
    }

    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(for: model))
    }

    func deleteModel(_ model: WhisperModel) throws {
        let path = modelPath(for: model)
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
    }

    func modelFileSize(_ model: WhisperModel) -> Int64? {
        let path = modelPath(for: model)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else { return nil }
        return size
    }

    private var modelsDirectory: String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("models").path
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progressCallback: (@Sendable (Double) -> Void)?

    init(progressCallback: (@Sendable (Double) -> Void)?) {
        self.progressCallback = progressCallback
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressCallback?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}

enum ModelManagerError: LocalizedError {
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let model): "Failed to download model: \(model)"
        }
    }
}
```

**Step 5: Build and verify**

```bash
xcodebuild -project MyWhispersIOS/MyWhispersIOS.xcodeproj -scheme MyWhispersIOS -sdk iphoneos build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

**Step 6: Commit**

```bash
git add MyWhispersIOS/Sources/Whisper/ MyWhispersIOS/Sources/App/Log.swift
git commit -m "feat(ios): port WhisperCppEngine, ModelManager, and WhisperModels from macOS"
```

---

## Task 4: AudioCapture for iOS

Port the audio capture, adapting for iOS AVAudioSession setup.

**Files:**
- Create: `MyWhispersIOS/Sources/Audio/AudioCapture.swift`
- Reference: `MyWhispers/Sources/Audio/AudioCapture.swift`

**Step 1: Create AudioCapture**

Create `MyWhispersIOS/Sources/Audio/AudioCapture.swift`:

```swift
import AVFoundation
import Foundation

final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        guard let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: nativeFormat, to: recordingFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }

        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let ratio = 16000.0 / nativeFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: recordingFormat,
                frameCapacity: outputFrameCount
            ) else { return }

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

            if error == nil, let channelData = convertedBuffer.floatChannelData?[0] {
                let samples = Array(UnsafeBufferPointer(
                    start: channelData,
                    count: Int(convertedBuffer.frameLength)
                ))
                self.bufferLock.lock()
                self.audioBuffer.append(contentsOf: samples)
                self.bufferLock.unlock()
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stopRecording() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        try? AVAudioSession.sharedInstance().setActive(false)

        bufferLock.lock()
        let samples = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()

        return samples
    }

    var sampleCount: Int {
        bufferLock.lock()
        let count = audioBuffer.count
        bufferLock.unlock()
        return count
    }

    /// Duration of captured audio in seconds (16kHz sample rate)
    var duration: TimeInterval {
        Double(sampleCount) / 16000.0
    }
}

enum AudioCaptureError: LocalizedError {
    case formatCreationFailed
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed: "Failed to create 16kHz audio format."
        case .converterCreationFailed: "Failed to create audio converter."
        }
    }
}
```

**Step 2: Build and verify**

```bash
xcodebuild -project MyWhispersIOS/MyWhispersIOS.xcodeproj -scheme MyWhispersIOS -sdk iphoneos build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add MyWhispersIOS/Sources/Audio/
git commit -m "feat(ios): add AudioCapture with AVAudioSession for iOS"
```

---

## Task 5: TranscriptionEngine (central state machine)

**Files:**
- Create: `MyWhispersIOS/Sources/App/TranscriptionEngine.swift`

**Step 1: Create the state machine**

Create `MyWhispersIOS/Sources/App/TranscriptionEngine.swift`:

```swift
import AVFoundation
import SwiftData
import SwiftUI
import UIKit

enum TranscriptionState: Equatable {
    case idle
    case recording(elapsed: TimeInterval)
    case transcribing
    case done(text: String)
    case error(message: String)
}

@Observable
@MainActor
final class TranscriptionEngine {
    var state: TranscriptionState = .idle
    var isModelLoaded = false
    var isDownloadingModel = false
    var downloadProgress: Double = 0
    var micPermissionGranted = false

    private let whisperEngine = WhisperCppEngine()
    private let modelManager = ModelManager.shared
    private let audioCapture = AudioCapture()
    private var timerTask: Task<Void, Never>?
    private var recordingStartTime: Date?
    private var modelContext: ModelContext?

    var selectedModel: WhisperModel {
        get { WhisperModel(rawValue: UserDefaults.standard.string(forKey: "selectedModel") ?? "base") ?? .base }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "selectedModel") }
    }

    var selectedLanguage: WhisperLanguage {
        get { WhisperLanguage(rawValue: UserDefaults.standard.string(forKey: "selectedLanguage") ?? "auto") ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "selectedLanguage") }
    }

    var autoCopy: Bool {
        get { UserDefaults.standard.object(forKey: "autoCopy") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoCopy") }
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Setup

    func setup() async {
        await checkMicPermission()
        await loadModel()
    }

    func checkMicPermission() async {
        let status = AVAudioApplication.shared.recordPermission
        switch status {
        case .undetermined:
            micPermissionGranted = await AudioCapture.requestPermission()
        case .granted:
            micPermissionGranted = true
        case .denied:
            micPermissionGranted = false
        @unknown default:
            micPermissionGranted = false
        }
    }

    func loadModel() async {
        let model = selectedModel
        isDownloadingModel = true
        downloadProgress = 0

        do {
            let path = try await modelManager.ensureModel(model) { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            }
            try await whisperEngine.loadModel(path: path)
            isModelLoaded = true
            isDownloadingModel = false
            Log.whisper.info("Model ready")
        } catch {
            isDownloadingModel = false
            state = .error(message: error.localizedDescription)
            Log.whisper.error("Model load failed: \(error)")
        }
    }

    // MARK: - Recording toggle

    func toggleRecording() {
        switch state {
        case .idle, .done, .error:
            startRecording()
        case .recording:
            Task { await stopAndTranscribe() }
        case .transcribing:
            break // Can't interrupt transcription
        }
    }

    private func startRecording() {
        guard isModelLoaded, micPermissionGranted else {
            state = .error(message: "Model not loaded or mic not granted")
            return
        }

        do {
            try audioCapture.startRecording()
            recordingStartTime = Date()
            state = .recording(elapsed: 0)

            timerTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled, let start = self.recordingStartTime else { break }
                    self.state = .recording(elapsed: Date().timeIntervalSince(start))
                }
            }

            Log.audio.info("Recording started")
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    private func stopAndTranscribe() async {
        timerTask?.cancel()
        timerTask = nil

        let duration = audioCapture.duration
        let samples = audioCapture.stopRecording()
        Log.audio.info("Recording stopped: \(samples.count) samples")

        guard !samples.isEmpty else {
            state = .idle
            return
        }

        state = .transcribing

        let langStr = selectedLanguage == .auto ? "auto" : selectedLanguage.rawValue
        let text = await whisperEngine.transcribe(samples: samples, language: langStr)

        if text.isEmpty {
            state = .error(message: "No speech detected")
            return
        }

        // Save to history
        if let ctx = modelContext {
            let transcription = Transcription(
                text: text,
                language: selectedLanguage.displayName,
                model: selectedModel.rawValue,
                duration: duration
            )
            ctx.insert(transcription)
        }

        // Auto-copy to clipboard
        if autoCopy {
            UIPasteboard.general.string = text
        }

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        state = .done(text: text)
        Log.whisper.info("Transcription complete")
    }
}
```

**Step 2: Build and verify**

```bash
xcodebuild -project MyWhispersIOS/MyWhispersIOS.xcodeproj -scheme MyWhispersIOS -sdk iphoneos build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add MyWhispersIOS/Sources/App/TranscriptionEngine.swift
git commit -m "feat(ios): add TranscriptionEngine state machine"
```

---

## Task 6: Main UI (recording screen + history)

**Files:**
- Modify: `MyWhispersIOS/Sources/App/MyWhispersIOSApp.swift`
- Create: `MyWhispersIOS/Sources/App/RecordingView.swift`

**Step 1: Create the recording view**

Create `MyWhispersIOS/Sources/App/RecordingView.swift`:

```swift
import SwiftUI

struct RecordingView: View {
    @Environment(TranscriptionEngine.self) private var engine

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            statusView

            recordButton

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var statusView: some View {
        switch engine.state {
        case .idle:
            VStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Tap to record")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

        case .recording(let elapsed):
            VStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
                Text(formatElapsed(elapsed))
                    .font(.system(.title, design: .monospaced))
                    .foregroundStyle(.red)
            }

        case .transcribing:
            VStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Transcribing...")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

        case .done(let text):
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text(text)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .padding(.horizontal)
                if engine.autoCopy {
                    Text("Copied to clipboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .error(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var recordButton: some View {
        Button {
            engine.toggleRecording()
        } label: {
            Circle()
                .fill(buttonColor)
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: buttonIcon)
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                }
        }
        .disabled(engine.state == .transcribing)
    }

    private var buttonColor: Color {
        switch engine.state {
        case .recording: .red
        case .transcribing: .gray
        default: .blue
        }
    }

    private var buttonIcon: String {
        switch engine.state {
        case .recording: "stop.fill"
        case .transcribing: "hourglass"
        default: "mic.fill"
        }
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", m, s, ms)
    }
}
```

**Step 2: Update the app entry point**

Update `MyWhispersIOS/Sources/App/MyWhispersIOSApp.swift`:

```swift
import SwiftUI
import SwiftData

@main
struct MyWhispersIOSApp: App {
    @State private var engine = TranscriptionEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engine)
                .onAppear {
                    Task { await engine.setup() }
                }
        }
        .modelContainer(for: Transcription.self)
    }
}

struct ContentView: View {
    @Environment(TranscriptionEngine.self) private var engine
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            Tab("Record", systemImage: "mic.fill") {
                RecordingView()
            }

            Tab("History", systemImage: "clock") {
                NavigationStack {
                    HistoryView()
                        .navigationTitle("History")
                }
            }

            Tab("Settings", systemImage: "gear") {
                NavigationStack {
                    Text("Settings")
                        .navigationTitle("Settings")
                }
            }
        }
        .onAppear {
            engine.setModelContext(modelContext)
        }
    }
}
```

**Step 3: Build and verify**

```bash
xcodebuild -project MyWhispersIOS/MyWhispersIOS.xcodeproj -scheme MyWhispersIOS -sdk iphoneos build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```bash
git add MyWhispersIOS/Sources/App/
git commit -m "feat(ios): add RecordingView and TabView-based main UI"
```

---

## Task 7: Settings view

**Files:**
- Create: `MyWhispersIOS/Sources/Settings/SettingsView.swift`

**Step 1: Create the settings view**

Create `MyWhispersIOS/Sources/Settings/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(TranscriptionEngine.self) private var engine

    var body: some View {
        @Bindable var engine = engine

        Form {
            Section("Whisper Model") {
                Picker("Model", selection: $engine.selectedModel) {
                    ForEach(WhisperModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .onChange(of: engine.selectedModel) {
                    Task { await engine.loadModel() }
                }

                if engine.isDownloadingModel {
                    ProgressView(value: engine.downloadProgress) {
                        Text("Downloading...")
                    }
                }
            }

            Section("Language") {
                Picker("Language", selection: $engine.selectedLanguage) {
                    ForEach(WhisperLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            }

            Section("Behavior") {
                Toggle("Auto-copy to clipboard", isOn: $engine.autoCopy)
            }

            Section("Storage") {
                ForEach(WhisperModel.allCases) { model in
                    ModelStorageRow(model: model)
                }
            }
        }
        .navigationTitle("Settings")
    }
}

struct ModelStorageRow: View {
    let model: WhisperModel
    @State private var isDownloaded = false
    @State private var fileSize: String = ""

    var body: some View {
        HStack {
            Text(model.displayName)
            Spacer()
            if isDownloaded {
                Text(fileSize)
                    .foregroundStyle(.secondary)
                Button("Delete", role: .destructive) {
                    Task {
                        try? await ModelManager.shared.deleteModel(model)
                        await checkStatus()
                    }
                }
                .buttonStyle(.borderless)
            } else {
                Text("Not downloaded")
                    .foregroundStyle(.secondary)
            }
        }
        .task { await checkStatus() }
    }

    private func checkStatus() async {
        isDownloaded = await ModelManager.shared.isModelDownloaded(model)
        if let size = await ModelManager.shared.modelFileSize(model) {
            fileSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
    }
}
```

**Step 2: Wire into ContentView**

Update the Settings tab in `ContentView`:

```swift
Tab("Settings", systemImage: "gear") {
    NavigationStack {
        SettingsView()
    }
}
```

**Step 3: Build and verify**

```bash
xcodebuild -project MyWhispersIOS/MyWhispersIOS.xcodeproj -scheme MyWhispersIOS -sdk iphoneos build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```bash
git add MyWhispersIOS/Sources/Settings/
git commit -m "feat(ios): add settings view with model picker, language, and storage management"
```

---

## Task 8: Live Activity + Dynamic Island

**Files:**
- Create: `MyWhispersIOS/MyWhispersIOSWidgetExtension/LiveActivityBundle.swift`
- Create: `MyWhispersIOS/MyWhispersIOSWidgetExtension/TranscriptionActivityWidget.swift`
- Create: `MyWhispersIOS/Sources/LiveActivity/TranscriptionActivity.swift`
- Modify: `MyWhispersIOS/Sources/App/TranscriptionEngine.swift` (add activity management)

**Step 1: Define the ActivityAttributes (shared between app and extension)**

Create `MyWhispersIOS/Sources/LiveActivity/TranscriptionActivity.swift`:

```swift
import ActivityKit
import Foundation

struct TranscriptionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: Status
        var elapsed: TimeInterval

        enum Status: String, Codable, Hashable {
            case recording
            case transcribing
        }
    }
}
```

**Step 2: Create the widget extension**

Create `MyWhispersIOS/MyWhispersIOSWidgetExtension/LiveActivityBundle.swift`:

```swift
import SwiftUI
import WidgetKit

@main
struct MyWhispersWidgetBundle: WidgetBundle {
    var body: some Widget {
        TranscriptionActivityWidget()
    }
}
```

Create `MyWhispersIOS/MyWhispersIOSWidgetExtension/TranscriptionActivityWidget.swift`:

```swift
import ActivityKit
import SwiftUI
import WidgetKit

struct TranscriptionActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TranscriptionActivityAttributes.self) { context in
            // Lock Screen view
            HStack {
                Image(systemName: context.state.status == .recording ? "mic.fill" : "waveform")
                    .foregroundStyle(context.state.status == .recording ? .red : .blue)

                VStack(alignment: .leading) {
                    Text(context.state.status == .recording ? "Recording..." : "Transcribing...")
                        .font(.headline)
                    Text(formatElapsed(context.state.elapsed))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.status == .recording ? "mic.fill" : "waveform")
                        .foregroundStyle(context.state.status == .recording ? .red : .blue)
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack {
                        Text(context.state.status == .recording ? "Recording" : "Transcribing")
                            .font(.headline)
                        Text(formatElapsed(context.state.elapsed))
                            .font(.system(.body, design: .monospaced))
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.status == .recording ? "mic.fill" : "waveform")
                    .foregroundStyle(context.state.status == .recording ? .red : .blue)
            } compactTrailing: {
                Text(formatElapsed(context.state.elapsed))
                    .font(.system(.caption, design: .monospaced))
            } minimal: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
```

**Step 3: Add Live Activity management to TranscriptionEngine**

Add these methods to `TranscriptionEngine`:

```swift
import ActivityKit

// Add property:
private var liveActivity: Activity<TranscriptionActivityAttributes>?

// Add to startRecording(), after state = .recording:
startLiveActivity()

// Add to stopAndTranscribe(), after state = .transcribing:
updateLiveActivity(status: .transcribing)

// Add to stopAndTranscribe(), at the end (after state = .done or .error):
endLiveActivity()

// New methods:
private func startLiveActivity() {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

    let attributes = TranscriptionActivityAttributes()
    let state = TranscriptionActivityAttributes.ContentState(status: .recording, elapsed: 0)

    do {
        liveActivity = try Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil)
        )
    } catch {
        Log.app.error("Failed to start Live Activity: \(error)")
    }
}

private func updateLiveActivity(status: TranscriptionActivityAttributes.ContentState.Status, elapsed: TimeInterval = 0) {
    Task {
        let state = TranscriptionActivityAttributes.ContentState(status: status, elapsed: elapsed)
        await liveActivity?.update(.init(state: state, staleDate: nil))
    }
}

private func endLiveActivity() {
    Task {
        await liveActivity?.end(nil, dismissalPolicy: .immediate)
        liveActivity = nil
    }
}
```

Also update the timer task in `startRecording()` to update the live activity:

```swift
timerTask = Task {
    while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled, let start = self.recordingStartTime else { break }
        let elapsed = Date().timeIntervalSince(start)
        self.state = .recording(elapsed: elapsed)
        self.updateLiveActivity(status: .recording, elapsed: elapsed)
    }
}
```

**Step 4: Configure the widget extension target in Xcode**

- Add a Widget Extension target named `MyWhispersIOSWidgetExtension`
- Deployment target: iOS 17.0
- Add `TranscriptionActivity.swift` to both the main app target AND the widget extension target
- Add `Supports Live Activities = YES` to the main app's Info.plist (`NSSupportsLiveActivities`)

**Step 5: Build and verify**

```bash
xcodebuild -project MyWhispersIOS/MyWhispersIOS.xcodeproj -scheme MyWhispersIOS -sdk iphoneos build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

**Step 6: Commit**

```bash
git add MyWhispersIOS/Sources/LiveActivity/ MyWhispersIOS/MyWhispersIOSWidgetExtension/
git commit -m "feat(ios): add Live Activity with Dynamic Island for recording status"
```

---

## Task 9: Action Button AppIntent

**Files:**
- Create: `MyWhispersIOS/Sources/Intents/ToggleRecordingIntent.swift`
- Create: `MyWhispersIOS/Sources/Intents/AppShortcuts.swift`

**Step 1: Create the AppIntent**

Create `MyWhispersIOS/Sources/Intents/ToggleRecordingIntent.swift`:

```swift
import AppIntents

struct ToggleRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Recording"
    static var description: IntentDescription = "Start or stop voice recording for transcription"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        TranscriptionEngineProvider.shared.engine.toggleRecording()
        return .result()
    }
}

/// Provides a shared TranscriptionEngine instance accessible from AppIntents.
@MainActor
final class TranscriptionEngineProvider {
    static let shared = TranscriptionEngineProvider()
    let engine = TranscriptionEngine()
}
```

> **Note:** The `TranscriptionEngineProvider` singleton ensures the AppIntent and the SwiftUI app share the same engine instance. Update `MyWhispersIOSApp` to use `TranscriptionEngineProvider.shared.engine` instead of creating its own instance.

**Step 2: Create AppShortcutsProvider**

Create `MyWhispersIOS/Sources/Intents/AppShortcuts.swift`:

```swift
import AppIntents

struct MyWhispersShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleRecordingIntent(),
            phrases: [
                "Transcribe with \(.applicationName)",
                "Record with \(.applicationName)",
                "Dictate with \(.applicationName)"
            ],
            shortTitle: "Transcribe",
            systemImageName: "mic.fill"
        )
    }
}
```

**Step 3: Update MyWhispersIOSApp to use the shared engine**

```swift
@main
struct MyWhispersIOSApp: App {
    @State private var engine = TranscriptionEngineProvider.shared.engine

    // ... rest stays the same
}
```

**Step 4: Build and verify**

```bash
xcodebuild -project MyWhispersIOS/MyWhispersIOS.xcodeproj -scheme MyWhispersIOS -sdk iphoneos build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

**Step 5: Commit**

```bash
git add MyWhispersIOS/Sources/Intents/
git commit -m "feat(ios): add Action Button AppIntent for toggle recording"
```

---

## Task 10: First-launch onboarding

**Files:**
- Create: `MyWhispersIOS/Sources/App/OnboardingView.swift`
- Modify: `MyWhispersIOS/Sources/App/MyWhispersIOSApp.swift`

**Step 1: Create onboarding view**

Create `MyWhispersIOS/Sources/App/OnboardingView.swift`:

```swift
import SwiftUI

struct OnboardingView: View {
    @Environment(TranscriptionEngine.self) private var engine
    @Binding var isComplete: Bool

    @State private var step = 0

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            switch step {
            case 0:
                welcomeStep
            case 1:
                micPermissionStep
            case 2:
                modelDownloadStep
            default:
                EmptyView()
            }

            Spacer()
        }
        .padding()
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
            Text("MyWhispers")
                .font(.largeTitle.bold())
            Text("Voice to text, powered by local AI.\nNo internet required.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Get Started") { step = 1 }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private var micPermissionStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.orange)
            Text("Microphone Access")
                .font(.title2.bold())
            Text("MyWhispers needs microphone access to record your voice.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Allow Microphone") {
                Task {
                    await engine.checkMicPermission()
                    step = 2
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var modelDownloadStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
            Text("Download Model")
                .font(.title2.bold())
            Text("Download the \(engine.selectedModel.displayName) speech recognition model.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Picker("Model", selection: Bindable(engine).selectedModel) {
                ForEach(WhisperModel.allCases) { model in
                    Text(model.displayName).tag(model)
                }
            }
            .pickerStyle(.segmented)

            if engine.isDownloadingModel {
                ProgressView(value: engine.downloadProgress) {
                    Text("Downloading... \(Int(engine.downloadProgress * 100))%")
                }
                .padding(.horizontal)
            } else if engine.isModelLoaded {
                Button("Done") {
                    UserDefaults.standard.set(true, forKey: "onboardingComplete")
                    isComplete = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button("Download & Continue") {
                    Task { await engine.loadModel() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
}
```

**Step 2: Wire onboarding into the app**

Update `MyWhispersIOSApp`:

```swift
@main
struct MyWhispersIOSApp: App {
    @State private var engine = TranscriptionEngineProvider.shared.engine
    @State private var onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")

    var body: some Scene {
        WindowGroup {
            if onboardingComplete {
                ContentView()
                    .environment(engine)
                    .onAppear {
                        Task { await engine.setup() }
                    }
            } else {
                OnboardingView(isComplete: $onboardingComplete)
                    .environment(engine)
            }
        }
        .modelContainer(for: Transcription.self)
    }
}
```

**Step 3: Build and verify**

```bash
xcodebuild -project MyWhispersIOS/MyWhispersIOS.xcodeproj -scheme MyWhispersIOS -sdk iphoneos build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```bash
git add MyWhispersIOS/Sources/App/OnboardingView.swift
git commit -m "feat(ios): add first-launch onboarding with mic permission and model download"
```

---

## Task 11: Info.plist, entitlements, and polish

**Files:**
- Modify: `MyWhispersIOS/Info.plist`
- Create: `MyWhispersIOS/MyWhispersIOS.entitlements`

**Step 1: Configure Info.plist**

Ensure these keys are set:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>MyWhispers needs microphone access to record your voice for transcription.</string>
<key>NSSupportsLiveActivities</key>
<true/>
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

**Step 2: Add .gitignore for vendor binaries**

Create/update `.gitignore` in `MyWhispersIOS/`:

```
Vendor/whisper-built/
```

**Step 3: Build and run on device**

```bash
xcodebuild -project MyWhispersIOS/MyWhispersIOS.xcodeproj -scheme MyWhispersIOS -sdk iphoneos -configuration Debug build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```bash
git add MyWhispersIOS/
git commit -m "feat(ios): configure Info.plist, entitlements, and gitignore"
```

---

## Summary

| Task | Description | Key Files |
|------|-------------|-----------|
| 0 | Cross-compile whisper.cpp for iOS | `Scripts/build-whisper-ios.sh` |
| 1 | Xcode project scaffold + C bridging | Project, `module.modulemap`, `MyWhispersIOSApp.swift` |
| 2 | SwiftData model + history view | `Transcription.swift`, `HistoryView.swift` |
| 3 | Whisper engine + model management | `WhisperCppEngine.swift`, `ModelManager.swift`, `WhisperModels.swift` |
| 4 | AudioCapture for iOS | `AudioCapture.swift` |
| 5 | TranscriptionEngine state machine | `TranscriptionEngine.swift` |
| 6 | Main UI (recording + tabs) | `RecordingView.swift`, updated `MyWhispersIOSApp.swift` |
| 7 | Settings view | `SettingsView.swift` |
| 8 | Live Activity + Dynamic Island | Widget extension, `TranscriptionActivity.swift` |
| 9 | Action Button AppIntent | `ToggleRecordingIntent.swift`, `AppShortcuts.swift` |
| 10 | First-launch onboarding | `OnboardingView.swift` |
| 11 | Info.plist + entitlements + polish | Config files |

**Dependencies**: Task 0 must complete before Task 1. Tasks 2-4 can run in parallel after Task 1. Task 5 depends on Tasks 3+4. Task 6 depends on Tasks 2+5. Tasks 7-10 depend on Task 6. Task 11 is final.
