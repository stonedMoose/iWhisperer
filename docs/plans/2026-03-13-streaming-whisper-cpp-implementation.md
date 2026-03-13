# Streaming Transcription with whisper.cpp — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace WhisperKit with whisper.cpp to add real-time streaming transcription using a sliding-window approach with word-level LocalAgreement.

**Architecture:** whisper.cpp is added as a git submodule and pre-compiled via CMake into a static library with Metal GPU support. A build script (`scripts/build-whisper.sh`) handles compilation. SPM references the pre-built library via a system library target. `WhisperCppEngine` provides a Swift actor wrapper around the C API. `ModelManager` handles GGML model download from HuggingFace. `AppState` gains a streaming mode with sliding-window inference and word-level stability confirmation.

**Tech Stack:** Swift, whisper.cpp (C via CMake), Metal GPU, AVAudioEngine, CGEvent

---

### Task 1: Add whisper.cpp as git submodule

**Files:**
- Create: `MyWhispers/Vendor/whisper.cpp/` (submodule)

**Step 1: Add the submodule**

```bash
cd /Users/julienlhermite/Projects/my-whispers/MyWhispers
git submodule add https://github.com/ggerganov/whisper.cpp.git Vendor/whisper.cpp
```

**Step 2: Pin to a known stable commit**

```bash
cd Vendor/whisper.cpp
git checkout $(git describe --tags --abbrev=0 2>/dev/null || git rev-parse HEAD)
cd ../..
```

**Step 3: Verify the submodule is checked out**

Run: `ls Vendor/whisper.cpp/include/whisper.h`
Expected: File exists

**Step 4: Commit**

```bash
cd /Users/julienlhermite/Projects/my-whispers
git add MyWhispers/Vendor/whisper.cpp .gitmodules
git commit -m "chore: add whisper.cpp as git submodule"
```

---

### Task 2: Create build script for whisper.cpp static library

**Files:**
- Create: `MyWhispers/scripts/build-whisper.sh`

**Step 1: Create the build script**

```bash
#!/bin/bash
# Build whisper.cpp into a static library with Metal support
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WHISPER_DIR="$PROJECT_DIR/Vendor/whisper.cpp"
BUILD_DIR="$PROJECT_DIR/.build/whisper-cpp"
INSTALL_DIR="$PROJECT_DIR/Vendor/whisper-built"

# Check if already built (skip rebuild for speed)
if [ -f "$INSTALL_DIR/lib/libwhisper.a" ] && [ -f "$INSTALL_DIR/lib/libggml.a" ]; then
    echo "whisper.cpp already built. Run with --clean to rebuild."
    if [ "${1:-}" != "--clean" ]; then
        exit 0
    fi
fi

if [ "${1:-}" = "--clean" ]; then
    rm -rf "$BUILD_DIR" "$INSTALL_DIR"
fi

echo "Building whisper.cpp with Metal support..."
mkdir -p "$BUILD_DIR"

cmake -B "$BUILD_DIR" -S "$WHISPER_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DGGML_ACCELERATE=ON \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF \
    -DBUILD_SHARED_LIBS=OFF

cmake --build "$BUILD_DIR" --config Release -j$(sysctl -n hw.logicalcpu)
cmake --install "$BUILD_DIR" --config Release

echo ""
echo "whisper.cpp built successfully:"
echo "  Headers: $INSTALL_DIR/include/"
echo "  Libraries: $INSTALL_DIR/lib/"
ls -la "$INSTALL_DIR/lib/"*.a
```

**Step 2: Make it executable**

Run: `chmod +x /Users/julienlhermite/Projects/my-whispers/MyWhispers/scripts/build-whisper.sh`

**Step 3: Run the build**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && ./scripts/build-whisper.sh`
Expected: Static libraries created at `Vendor/whisper-built/lib/libwhisper.a` and `Vendor/whisper-built/lib/libggml.a`

**Step 4: Add the built artifacts to .gitignore**

Add to the project's `.gitignore`:
```
MyWhispers/Vendor/whisper-built/
MyWhispers/.build/whisper-cpp/
```

**Step 5: Commit**

```bash
cd /Users/julienlhermite/Projects/my-whispers
git add MyWhispers/scripts/build-whisper.sh .gitignore
git commit -m "build: add whisper.cpp build script with Metal support"
```

---

### Task 3: Create C module map and configure Package.swift

**Files:**
- Create: `MyWhispers/Vendor/CWhisper/module.modulemap`
- Create: `MyWhispers/Vendor/CWhisper/shim.h`
- Modify: `MyWhispers/Package.swift`

**Step 1: Create the module directory**

```bash
mkdir -p /Users/julienlhermite/Projects/my-whispers/MyWhispers/Vendor/CWhisper
```

**Step 2: Create the shim header** at `MyWhispers/Vendor/CWhisper/shim.h`

```c
#ifndef CWHISPER_SHIM_H
#define CWHISPER_SHIM_H

#include "whisper.h"

#endif
```

**Step 3: Create the module map** at `MyWhispers/Vendor/CWhisper/module.modulemap`

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

**Step 4: Replace Package.swift entirely**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyWhispers",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .systemLibrary(
            name: "CWhisper",
            path: "Vendor/CWhisper",
            pkgConfig: nil,
            providers: []
        ),
        .executableTarget(
            name: "MyWhispers",
            dependencies: [
                "CWhisper",
                "KeyboardShortcuts",
            ],
            path: "Sources",
            exclude: ["Info.plist"],
            resources: [
                .process("../Resources"),
            ],
            cSettings: [
                .headerSearchPath("../Vendor/whisper-built/include"),
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-I", "Vendor/whisper-built/include",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", "Vendor/whisper-built/lib",
                ]),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
                .linkedLibrary("c++"),
            ]
        ),
    ]
)
```

**Step 5: Build to verify the setup**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -20`
Expected: Build may fail because WhisperKit imports are still in the code — that's OK for now. We're just verifying the C library links.

**Step 6: Commit**

```bash
cd /Users/julienlhermite/Projects/my-whispers
git add MyWhispers/Vendor/CWhisper/ MyWhispers/Package.swift
git commit -m "build: configure Package.swift with CWhisper system library

Replace WhisperKit dependency with CWhisper system library target
pointing to pre-built whisper.cpp static libraries with Metal support."
```

---

### Task 4: Create WhisperCppEngine (Swift wrapper)

**Files:**
- Create: `MyWhispers/Sources/Whisper/WhisperCppEngine.swift`

**Step 1: Create the file**

```swift
import CWhisper
import Foundation
import OSLog

actor WhisperCppEngine {
    private var ctx: OpaquePointer?
    private var currentModelPath: String?

    var isLoaded: Bool { ctx != nil }

    /// Load a GGML model from the given file path.
    func loadModel(path: String) throws {
        unloadModel()

        var params = whisper_context_default_params()
        params.use_gpu = true
        params.flash_attn = true

        guard let context = whisper_init_from_file_with_params(path, params) else {
            throw WhisperCppError.modelLoadFailed(path)
        }

        ctx = context
        currentModelPath = path
        Log.whisper.info("whisper.cpp model loaded: \(path)")
    }

    /// Unload the current model and free resources.
    func unloadModel() {
        if let ctx {
            whisper_free(ctx)
        }
        ctx = nil
        currentModelPath = nil
    }

    deinit {
        if let ctx {
            whisper_free(ctx)
        }
    }

    /// Transcribe audio samples (16kHz Float32) to text.
    func transcribe(samples: [Float], language: String) -> String {
        guard let ctx else { return "" }

        let maxThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_special = false
        params.print_timestamps = false
        params.translate = false
        params.single_segment = false
        params.no_context = true
        params.n_threads = Int32(maxThreads)

        let lang = language == "auto" ? nil : language
        let result: Int32 = lang.withOptionalCString { langPtr in
            params.language = langPtr
            return samples.withUnsafeBufferPointer { samplesPtr in
                whisper_full(ctx, params, samplesPtr.baseAddress, Int32(samplesPtr.count))
            }
        }

        guard result == 0 else {
            Log.whisper.error("whisper_full failed with code \(result)")
            return ""
        }

        return collectSegmentText()
    }

    /// Transcribe a sliding window of audio, returning text and token IDs for prompt context.
    func transcribeWindow(samples: [Float], language: String,
                          promptTokens: [whisper_token]) -> (text: String, tokens: [whisper_token]) {
        guard let ctx else { return ("", []) }

        let maxThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_special = false
        params.print_timestamps = false
        params.translate = false
        params.single_segment = true
        params.no_context = promptTokens.isEmpty
        params.n_threads = Int32(maxThreads)
        params.no_timestamps = true

        let lang = language == "auto" ? nil : language

        let result: Int32 = lang.withOptionalCString { langPtr in
            params.language = langPtr

            // Feed prompt tokens for cross-chunk coherence
            return promptTokens.withUnsafeBufferPointer { promptPtr in
                if !promptTokens.isEmpty {
                    params.prompt_tokens = promptPtr.baseAddress
                    params.prompt_n_tokens = Int32(promptPtr.count)
                }
                return samples.withUnsafeBufferPointer { samplesPtr in
                    whisper_full(ctx, params, samplesPtr.baseAddress, Int32(samplesPtr.count))
                }
            }
        }

        guard result == 0 else {
            Log.whisper.error("whisper_full (window) failed with code \(result)")
            return ("", [])
        }

        let text = collectSegmentText()
        let tokens = collectTokenIds()
        return (text, tokens)
    }

    // MARK: - Private

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

    private func collectTokenIds() -> [whisper_token] {
        guard let ctx else { return [] }
        var tokens: [whisper_token] = []
        let nSegments = whisper_full_n_segments(ctx)
        for i in 0..<nSegments {
            let nTokens = whisper_full_n_tokens(ctx, i)
            for j in 0..<nTokens {
                let tokenId = whisper_full_get_token_id(ctx, i, j)
                tokens.append(tokenId)
            }
        }
        return tokens
    }

    /// Remove Whisper special tokens like <|en|>, <|transcribe|>, etc.
    private func cleanText(_ text: String) -> String {
        text.replacingOccurrences(
            of: "<\\|[^|]*\\|>",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Helper

private extension Optional where Wrapped == String {
    func withOptionalCString<R>(_ body: (UnsafePointer<CChar>?) -> R) -> R {
        switch self {
        case .some(let string):
            return string.withCString { body($0) }
        case .none:
            return body(nil)
        }
    }
}

enum WhisperCppError: LocalizedError {
    case modelLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path): "Failed to load whisper model at: \(path)"
        }
    }
}
```

**Step 2: Build to verify it compiles**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -10`
Expected: May fail on other files still importing WhisperKit, but WhisperCppEngine.swift should compile. Check for errors specifically in this file.

**Step 3: Commit**

```bash
cd /Users/julienlhermite/Projects/my-whispers
git add MyWhispers/Sources/Whisper/WhisperCppEngine.swift
git commit -m "feat: add WhisperCppEngine actor wrapping whisper.cpp C API

Provides batch transcription and sliding-window transcription with
prompt token context feeding. Uses Metal GPU and flash attention."
```

---

### Task 5: Create ModelManager for GGML model download

**Files:**
- Create: `MyWhispers/Sources/Whisper/ModelManager.swift`

**Step 1: Create the file**

```swift
import Foundation
import OSLog

actor ModelManager {
    static let shared = ModelManager()

    private var downloadTask: URLSessionDownloadTask?
    private var progressContinuation: AsyncStream<Double>.Continuation?

    /// Download a GGML model from HuggingFace if not already cached.
    /// Returns the local file path.
    func ensureModel(_ model: WhisperModel, progressCallback: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        let path = modelPath(for: model)

        if FileManager.default.fileExists(atPath: path) {
            Log.whisper.info("Model already cached: \(path)")
            progressCallback?(1.0)
            return path
        }

        let dir = modelsDirectory
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let url = model.downloadURL
        Log.whisper.info("Downloading model from \(url.absoluteString)")

        let delegate = DownloadDelegate(progressCallback: progressCallback)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (tempURL, response) = try await session.download(from: url, delegate: delegate)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ModelManagerError.downloadFailed(model.rawValue)
        }

        try FileManager.default.moveItem(atPath: tempURL.path, toPath: path)
        Log.whisper.info("Model downloaded to \(path)")
        return path
    }

    func modelPath(for model: WhisperModel) -> String {
        modelsDirectory + "/ggml-\(model.ggmlName).bin"
    }

    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(for: model))
    }

    private var modelsDirectory: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MyWhispers/models").path
    }
}

// MARK: - Download delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progressCallback: (@Sendable (Double) -> Void)?

    init(progressCallback: (@Sendable (Double) -> Void)?) {
        self.progressCallback = progressCallback
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressCallback?(progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // handled by the async download call
    }
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

**Step 2: Commit**

```bash
cd /Users/julienlhermite/Projects/my-whispers
git add MyWhispers/Sources/Whisper/ModelManager.swift
git commit -m "feat: add ModelManager actor for GGML model download

Downloads models from HuggingFace ggerganov/whisper.cpp repo.
Caches in ~/Library/Application Support/MyWhispers/models/."
```

---

### Task 6: Update WhisperModels for GGML naming

**Files:**
- Modify: `MyWhispers/Sources/Whisper/WhisperModels.swift`

**Step 1: Add GGML-specific properties to WhisperModel**

Add after line 9 (`case largev3 = "large-v3"`), before line 11 (`var id: String { rawValue }`):

```swift
    /// The GGML filename component (e.g., "large-v3" for ggml-large-v3.bin)
    var ggmlName: String { rawValue }

    /// HuggingFace download URL for the GGML model file.
    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(ggmlName).bin")!
    }
```

**Step 2: Update display names to reflect GGML sizes**

Replace the `displayName` computed property (lines 13-19) with:

```swift
    var displayName: String {
        switch self {
        case .tiny: "Tiny (~75 MB)"
        case .base: "Base (~140 MB)"
        case .small: "Small (~460 MB)"
        case .medium: "Medium (~1.5 GB)"
        case .largev3: "Large v3 (~3 GB)"
        }
    }
```

(These sizes are similar to WhisperKit, so the display names stay the same.)

**Step 3: Build and verify**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | grep -i "error" | head -5`

**Step 4: Commit**

```bash
cd /Users/julienlhermite/Projects/my-whispers
git add MyWhispers/Sources/Whisper/WhisperModels.swift
git commit -m "feat: add GGML download URL and naming to WhisperModel"
```

---

### Task 7: Add getWindow() to AudioCapture

**Files:**
- Modify: `MyWhispers/Sources/Audio/AudioCapture.swift`

**Step 1: Add the getWindow method**

Add after line 84 (`return samples`), before line 85 (`}`):

```swift

    /// Return the last `lengthMs` of audio, retaining `keepMs` overlap context.
    /// Used by streaming mode to get a sliding window of audio.
    func getWindow(lengthMs: Int, keepMs: Int) -> [Float] {
        bufferLock.lock()
        let allSamples = audioBuffer
        bufferLock.unlock()

        let lengthSamples = lengthMs * 16  // 16kHz = 16 samples per ms
        let maxSamples = min(allSamples.count, lengthSamples)

        if maxSamples <= 0 { return [] }

        // Take the last `maxSamples` from the buffer
        return Array(allSamples.suffix(maxSamples))
    }

    /// Return all samples captured so far without clearing the buffer.
    func peekSamples() -> [Float] {
        bufferLock.lock()
        let samples = audioBuffer
        bufferLock.unlock()
        return samples
    }

    /// Current number of captured samples.
    var sampleCount: Int {
        bufferLock.lock()
        let count = audioBuffer.count
        bufferLock.unlock()
        return count
    }
```

**Step 2: Update the comment on line 18 to reference whisper.cpp instead of WhisperKit**

Replace line 18:
```swift
    /// Start capturing audio from the microphone at 16kHz mono (what WhisperKit expects).
```
With:
```swift
    /// Start capturing audio from the microphone at 16kHz mono (what whisper.cpp expects).
```

**Step 3: Build and verify**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`

**Step 4: Commit**

```bash
cd /Users/julienlhermite/Projects/my-whispers
git add MyWhispers/Sources/Audio/AudioCapture.swift
git commit -m "feat: add getWindow() and peekSamples() to AudioCapture

getWindow() returns a sliding window of audio for streaming mode.
peekSamples() returns all buffered samples without clearing."
```

---

### Task 8: Add streaming toggle to SettingsStore

**Files:**
- Modify: `MyWhispers/Sources/Settings/SettingsStore.swift`

**Step 1: Add streamingMode property**

Add after line 19 (`@AppStorage("launchAtLogin") private var _launchAtLogin: Bool = false`):

```swift

    @ObservationIgnored
    @AppStorage("streamingMode") private var _streamingMode: Bool = false
```

**Step 2: Add computed property wrapper**

Add after the `launchAtLogin` computed property (after line 84, before the closing `}` of the class on line 85):

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
```

**Step 3: Commit**

```bash
cd /Users/julienlhermite/Projects/my-whispers
git add MyWhispers/Sources/Settings/SettingsStore.swift
git commit -m "feat: add streaming mode toggle to SettingsStore"
```

---

### Task 9: Add streaming toggle to SettingsView

**Files:**
- Modify: `MyWhispers/Sources/Settings/SettingsView.swift`

**Step 1: Add streaming section after the General section**

Replace lines 66-67 (the `Spacer()` + closing `}` of the left VStack):

```swift
                Spacer()
            }
```

With:

```swift
                Divider()

                // Streaming
                VStack(alignment: .leading, spacing: 8) {
                    Label("Streaming", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.headline)

                    Toggle("Enable streaming mode", isOn: $settings.streamingMode)

                    Text("Type text progressively as you speak instead of waiting until you stop recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
```

**Step 2: Build and verify**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`

**Step 3: Commit**

```bash
cd /Users/julienlhermite/Projects/my-whispers
git add MyWhispers/Sources/Settings/SettingsView.swift
git commit -m "feat: add streaming mode toggle to settings UI"
```

---

### Task 10: Replace WhisperEngine with WhisperCppEngine in AppState

**Files:**
- Modify: `MyWhispers/Sources/App/AppState.swift`

This task replaces the WhisperKit engine with whisper.cpp for batch mode. Streaming is added in the next task.

**Step 1: Replace the import and engine**

Replace line 1-5:

```swift
import AVFoundation
import OSLog
import SwiftUI
import KeyboardShortcuts

```

With:

```swift
import AVFoundation
import OSLog
import SwiftUI
import KeyboardShortcuts

```

(Imports stay the same — WhisperKit was never imported here.)

Replace line 21:

```swift
    private let whisperEngine = WhisperEngine()
```

With:

```swift
    private let whisperEngine = WhisperCppEngine()
    private let modelManager = ModelManager.shared
```

**Step 2: Replace the loadModel() method (lines 165-186)**

Replace:

```swift
    func loadModel() async {
        isModelLoaded = false
        isDownloadingModel = false
        downloadProgress = 0
        let model = settingsStore.selectedModel
        downloadingModelName = model.displayName
        do {
            Log.whisper.info("Loading model: \(model.rawValue)")
            isDownloadingModel = true
            try await whisperEngine.loadModel(model) { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            }
            isDownloadingModel = false
            isModelLoaded = true
            Log.whisper.info("Model loaded successfully")
        } catch {
            isDownloadingModel = false
            Log.whisper.error("Failed to load model: \(error)")
        }
    }
```

With:

```swift
    func loadModel() async {
        isModelLoaded = false
        isDownloadingModel = false
        downloadProgress = 0
        let model = settingsStore.selectedModel
        downloadingModelName = model.displayName
        do {
            Log.whisper.info("Loading model: \(model.rawValue)")
            isDownloadingModel = true
            let path = try await modelManager.ensureModel(model) { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            }
            try await whisperEngine.loadModel(path: path)
            isDownloadingModel = false
            isModelLoaded = true
            Log.whisper.info("Model loaded successfully")
        } catch {
            isDownloadingModel = false
            Log.whisper.error("Failed to load model: \(error)")
        }
    }
```

**Step 3: Replace the transcription call in stopRecordingAndTranscribe() (lines 234-238)**

Replace:

```swift
            let text = try await whisperEngine.transcribe(
                audioSamples: samples,
                language: settingsStore.selectedLanguage
            )
```

With:

```swift
            let language = settingsStore.selectedLanguage
            let text = await whisperEngine.transcribe(
                samples: samples,
                language: language == .auto ? "auto" : language.rawValue
            )
```

Also remove the `do/catch` around it and adjust — the new `transcribe` returns `String` (never throws). Replace the whole block from line 231 to 248:

```swift
        isProcessing = true
        recordingIndicator.showProcessing()

        let language = settingsStore.selectedLanguage
        let text = await whisperEngine.transcribe(
            samples: samples,
            language: language == .auto ? "auto" : language.rawValue
        )
        Log.whisper.info("Transcription result: \(text)")
        if !text.isEmpty {
            TextInjector.typeText(text)
        }

        isProcessing = false
        recordingIndicator.hide()
```

**Step 4: Build and verify**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -10`
Expected: Build succeeds (or only unrelated warnings)

**Step 5: Commit**

```bash
cd /Users/julienlhermite/Projects/my-whispers
git add MyWhispers/Sources/App/AppState.swift
git commit -m "feat: replace WhisperKit with WhisperCppEngine in AppState

Batch transcription now uses whisper.cpp via WhisperCppEngine.
Model download via ModelManager from HuggingFace GGML repository."
```

---

### Task 11: Remove old WhisperEngine and WhisperKit dependency

**Files:**
- Delete: `MyWhispers/Sources/Whisper/WhisperEngine.swift`

**Step 1: Delete the old engine**

```bash
rm /Users/julienlhermite/Projects/my-whispers/MyWhispers/Sources/Whisper/WhisperEngine.swift
```

**Step 2: Verify no code still references WhisperEngine or WhisperKit**

Run: `grep -r "WhisperEngine\|WhisperKit\|import WhisperKit" /Users/julienlhermite/Projects/my-whispers/MyWhispers/Sources/ 2>/dev/null`
Expected: No matches (except possibly in comments or the new WhisperCppEngine file name)

**Step 3: Build**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -10`
Expected: Build succeeds

**Step 4: Commit**

```bash
cd /Users/julienlhermite/Projects/my-whispers
git add -A MyWhispers/Sources/Whisper/WhisperEngine.swift
git commit -m "refactor: remove WhisperEngine and WhisperKit dependency

WhisperKit has been fully replaced by whisper.cpp via WhisperCppEngine."
```

---

### Task 12: Add streaming mode to AppState

**Files:**
- Modify: `MyWhispers/Sources/App/AppState.swift`

This is the core streaming feature. AppState gains a sliding-window loop with word-level LocalAgreement.

**Step 1: Add streaming state properties**

After the existing `private var permissionPollTask: Task<Void, Never>?` (line 26), add:

```swift
    private var streamingLoopTask: Task<Void, Never>?
    private var streamingTypedWordCount = 0
    private var streamingPreviousWords: [String] = []
    private var streamingPromptTokens: [Int32] = []

    private static let streamStepMs = 3000
    private static let streamLengthMs = 10000
    private static let streamKeepMs = 200
```

**Step 2: Replace the startRecording() method**

Replace the current `startRecording()` method with:

```swift
    private func startRecording() {
        guard isModelLoaded, !isProcessing else { return }

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

**Step 3: Replace the stopRecordingAndTranscribe() method and everything after it**

Replace everything from `private func stopRecordingAndTranscribe()` through the end of the class with:

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

        let language = settingsStore.selectedLanguage
        let text = await whisperEngine.transcribe(
            samples: samples,
            language: language == .auto ? "auto" : language.rawValue
        )
        Log.whisper.info("Transcription result: \(text)")
        if !text.isEmpty {
            TextInjector.typeText(text)
        }

        isProcessing = false
        recordingIndicator.hide()
    }

    // MARK: - Streaming mode (sliding window + LocalAgreement)

    private func startStreamingRecording() {
        streamingTypedWordCount = 0
        streamingPreviousWords = []
        streamingPromptTokens = []

        do {
            try audioCapture.startRecording()
            guard recordingIndicator.show() else {
                _ = audioCapture.stopRecording()
                return
            }
            isRecording = true
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

            let window = audioCapture.getWindow(
                lengthMs: Self.streamLengthMs,
                keepMs: Self.streamKeepMs
            )
            guard window.count >= minSamples else { continue }

            let language = settingsStore.selectedLanguage
            let langStr = language == .auto ? "auto" : language.rawValue

            let (text, tokens) = await whisperEngine.transcribeWindow(
                samples: window,
                language: langStr,
                promptTokens: streamingPromptTokens
            )

            guard !Task.isCancelled else { break }

            let currentWords = Self.splitIntoWords(text)
            guard !currentWords.isEmpty else {
                streamingPreviousWords = []
                continue
            }

            // Word-level LocalAgreement: longest common word prefix
            let stableCount = Self.longestCommonWordPrefix(currentWords, streamingPreviousWords)
            streamingPreviousWords = currentWords

            // Type only newly confirmed words
            if stableCount > streamingTypedWordCount {
                let newWords = Array(currentWords[streamingTypedWordCount..<stableCount])
                let prefix = streamingTypedWordCount == 0 ? "" : " "
                let newText = prefix + newWords.joined(separator: " ")
                if !newText.isEmpty {
                    Log.whisper.info("Streaming text: \(newText)")
                    TextInjector.typeText(newText)
                    streamingTypedWordCount = stableCount
                }
            }

            // Feed tokens as prompt context for next iteration
            streamingPromptTokens = tokens
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

        // Final full inference on all captured audio
        let language = settingsStore.selectedLanguage
        let langStr = language == .auto ? "auto" : language.rawValue
        let finalText = await whisperEngine.transcribe(samples: samples, language: langStr)
        let finalWords = Self.splitIntoWords(finalText)

        if finalWords.count > streamingTypedWordCount {
            let remaining = Array(finalWords[streamingTypedWordCount...])
            let prefix = streamingTypedWordCount == 0 ? "" : " "
            let remainingText = prefix + remaining.joined(separator: " ")
            if !remainingText.isEmpty {
                Log.whisper.info("Streaming final: \(remainingText)")
                TextInjector.typeText(remainingText)
            }
        } else if streamingTypedWordCount == 0 && !finalText.isEmpty {
            Log.whisper.info("Streaming fallback: \(finalText)")
            TextInjector.typeText(finalText)
        }

        streamingTypedWordCount = 0
        streamingPreviousWords = []
        streamingPromptTokens = []
        isProcessing = false
        recordingIndicator.hide()
    }

    // MARK: - LocalAgreement helpers

    /// Split text into words, filtering empty strings.
    private static func splitIntoWords(_ text: String) -> [String] {
        text.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    /// Longest common word prefix between two word arrays.
    private static func longestCommonWordPrefix(_ a: [String], _ b: [String]) -> Int {
        var count = 0
        for (wa, wb) in zip(a, b) {
            if wa == wb { count += 1 } else { break }
        }
        return count
    }
}
```

**Step 4: Build and verify**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -10`
Expected: Build succeeds

**Step 5: Commit**

```bash
cd /Users/julienlhermite/Projects/my-whispers
git add MyWhispers/Sources/App/AppState.swift
git commit -m "feat: add streaming mode with sliding-window LocalAgreement

When streaming mode is enabled in settings:
- AudioCapture provides sliding window (10s window, 3s step)
- whisper.cpp runs inference every 3s on the window
- Word-level LocalAgreement confirms stable text before typing
- Prompt tokens fed across windows for coherence
- Final full inference on stop fills remaining text
- Batch mode remains unchanged when streaming is disabled"
```

---

### Task 13: Update bundle script to build whisper.cpp first

**Files:**
- Modify: `MyWhispers/scripts/bundle.sh`

**Step 1: Add whisper.cpp build step**

Add after line 8 (`BUILD_DIR="$PROJECT_DIR/.build/release"`), before line 10 (`echo "Building release..."`):

```bash

echo "Building whisper.cpp..."
"$SCRIPT_DIR/build-whisper.sh"

```

**Step 2: Commit**

```bash
cd /Users/julienlhermite/Projects/my-whispers
git add MyWhispers/scripts/bundle.sh
git commit -m "build: run whisper.cpp build before app build in bundle script"
```

---

### Task 14: Manual testing — batch mode

**No code changes — verification only.**

**Step 1: Build whisper.cpp**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && ./scripts/build-whisper.sh`
Expected: Libraries built at `Vendor/whisper-built/lib/`

**Step 2: Build the app**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build`
Expected: Build succeeds

**Step 3: Run the app**

Run: `.build/debug/MyWhispers`

**Step 4: Test batch mode**

1. Ensure "Enable streaming mode" is OFF in Settings
2. First run: wait for model download (check menu bar shows "Downloading model...")
3. After download: menu bar shows "Ready"
4. Hold the hotkey, say "Hello world this is a test", release
5. Verify text appears at cursor
6. Check Console.app for "Transcription result:" log

---

### Task 15: Manual testing — streaming mode

**No code changes — verification only.**

**Step 1: Enable streaming in Settings**

1. Open Settings, enable "Enable streaming mode" toggle

**Step 2: Short recording (< 6 seconds)**

1. Hold the hotkey, say "Hello world", release quickly (~3s)
2. After release: text should appear (via final inference)
3. Check Console.app for "Streaming fallback:" or "Streaming final:" log

**Step 3: Medium recording (~10 seconds)**

1. Hold the hotkey, speak a full sentence for ~10 seconds
2. After ~6 seconds: first stable words should start appearing
3. On release: remaining text appears
4. Check Console.app for "Streaming text:" logs during recording

**Step 4: Long recording (~20+ seconds)**

1. Hold the hotkey, speak continuously for 20+ seconds
2. Text should appear incrementally every ~6 seconds (2 agreements needed)
3. On release: final words appear
4. Quality should be comparable to batch mode

**Step 5: Verify batch mode still works**

1. Disable "Enable streaming mode" in Settings
2. Hold hotkey, speak, release
3. Verify identical behavior to before streaming was added
