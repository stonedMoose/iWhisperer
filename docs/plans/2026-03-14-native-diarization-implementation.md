# Native Speaker Diarization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a built-in speaker diarization option using sherpa-onnx + TitaNet, so users don't need a HuggingFace token for meeting transcription with speaker labels.

**Architecture:** Vendor sherpa-onnx as a pre-built C library (same pattern as whisper.cpp). Add a `DiarizationEngine` setting that switches between the new native pipeline (whisper.cpp transcription + sherpa-onnx diarization) and the existing WhisperX/pyannote pipeline. A new `SherpaOnnxDiarizer` actor handles the native diarization, and a merge step aligns speaker labels with whisper.cpp transcript segments by timestamp overlap.

**Tech Stack:** sherpa-onnx (C API), ONNX Runtime, TitaNet-Large ONNX, Silero VAD v6 ONNX, Swift, SwiftUI

---

### Task 1: Build and Vendor sherpa-onnx C Library

**Files:**
- Create: `Vendor/CSherpaOnnx/module.modulemap`
- Create: `Vendor/CSherpaOnnx/shim.h`
- Create: `Vendor/sherpa-onnx-built/lib/` (pre-built static libraries)
- Create: `Vendor/sherpa-onnx-built/include/` (C headers)

**Step 1: Clone and build sherpa-onnx for macOS**

```bash
cd /tmp
git clone https://github.com/k2-fsa/sherpa-onnx.git
cd sherpa-onnx
mkdir build && cd build
cmake .. \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DSHERPA_ONNX_ENABLE_C_API=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DSHERPA_ONNX_ENABLE_BINARY=OFF
make -j$(sysctl -n hw.ncpu)
```

Expected: Static libraries (`.a`) and C headers produced in build output.

**Step 2: Copy build artifacts into vendor directory**

```bash
cd /Users/julienlhermite/Projects/my-whispers/MyWhispers
mkdir -p Vendor/sherpa-onnx-built/lib Vendor/sherpa-onnx-built/include Vendor/CSherpaOnnx

# Copy headers (sherpa-onnx C API header)
cp /tmp/sherpa-onnx/sherpa-onnx/c-api/c-api.h Vendor/sherpa-onnx-built/include/sherpa-onnx-c-api.h

# Copy static libraries (exact names depend on build output — typically):
# libsherpa-onnx-c-api.a, libsherpa-onnx-core.a, libonnxruntime.a, libkaldi-native-fbank-core.a
cp /tmp/sherpa-onnx/build/lib/*.a Vendor/sherpa-onnx-built/lib/
```

**Step 3: Create the C module bridge**

Create `Vendor/CSherpaOnnx/shim.h`:
```c
#ifndef CSHERPAONNX_SHIM_H
#define CSHERPAONNX_SHIM_H

#include "sherpa-onnx-c-api.h"

#endif
```

Create `Vendor/CSherpaOnnx/module.modulemap`:
```
module CSherpaOnnx {
    header "shim.h"
    link "sherpa-onnx-c-api"
    link "sherpa-onnx-core"
    link "onnxruntime"
    link "kaldi-native-fbank-core"
    export *
}
```

Note: The exact library names depend on the build output. Adjust `link` directives to match the actual `.a` file names (minus the `lib` prefix and `.a` suffix).

**Step 4: Update Package.swift to add CSherpaOnnx target**

In `Package.swift`, add a new system library target and link it to the main target:

```swift
// Add to targets array:
.systemLibrary(
    name: "CSherpaOnnx",
    path: "Vendor/CSherpaOnnx",
    pkgConfig: nil,
    providers: []
),

// Add "CSherpaOnnx" to executableTarget dependencies:
dependencies: [
    "CWhisper",
    "CSherpaOnnx",
    "KeyboardShortcuts",
],

// Add to cSettings:
.headerSearchPath("../Vendor/sherpa-onnx-built/include"),

// Add to swiftSettings unsafeFlags:
"-I", "Vendor/sherpa-onnx-built/include",

// Add to linkerSettings unsafeFlags:
"-L", "Vendor/sherpa-onnx-built/lib",
```

**Step 5: Verify it compiles**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`
Expected: Build succeeds (or at least links without undefined symbols from sherpa-onnx).

**Step 6: Commit**

```bash
git add Vendor/CSherpaOnnx/ Vendor/sherpa-onnx-built/ Package.swift
git commit -m "feat: vendor sherpa-onnx C library for native diarization"
```

---

### Task 2: Add DiarizationEngine Setting

**Files:**
- Modify: `Sources/Settings/SettingsStore.swift`
- Modify: `Sources/Whisper/WhisperModels.swift`

**Step 1: Add DiarizationEngine enum**

In `Sources/Whisper/WhisperModels.swift`, add at the end of the file:

```swift
enum DiarizationEngine: String, CaseIterable, Identifiable, Codable {
    case builtIn = "builtIn"
    case whisperX = "whisperX"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .builtIn: "Built-in (TitaNet)"
        case .whisperX: "WhisperX (pyannote)"
        }
    }
}
```

**Step 2: Add setting to SettingsStore**

In `Sources/Settings/SettingsStore.swift`, add after the `_transcriptDirectory` property (line 28):

```swift
@ObservationIgnored
@AppStorage("diarizationEngine") private var _diarizationEngine: DiarizationEngine = .builtIn
```

And add the computed property after the `transcriptDirectory` computed property (after line 132):

```swift
var diarizationEngine: DiarizationEngine {
    get {
        access(keyPath: \.diarizationEngine)
        return _diarizationEngine
    }
    set {
        withMutation(keyPath: \.diarizationEngine) {
            _diarizationEngine = newValue
        }
    }
}
```

**Step 3: Verify it compiles**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`
Expected: Build succeeds.

**Step 4: Commit**

```bash
git add Sources/Settings/SettingsStore.swift Sources/Whisper/WhisperModels.swift
git commit -m "feat: add DiarizationEngine enum and setting"
```

---

### Task 3: Update Settings UI

**Files:**
- Modify: `Sources/Settings/SettingsView.swift`

**Step 1: Replace the HuggingFace section with engine picker + conditional HF token**

In `Sources/Settings/SettingsView.swift`, replace the entire HuggingFace VStack (lines 58-73) with:

```swift
VStack(alignment: .leading, spacing: 8) {
    Label("Diarization", systemImage: "person.wave.2")
        .font(.headline)

    Picker("", selection: $settings.diarizationEngine) {
        ForEach(DiarizationEngine.allCases) { engine in
            Text(engine.displayName).tag(engine)
        }
    }
    .labelsHidden()

    if settings.diarizationEngine == .whisperX {
        SecureField("HuggingFace Token", text: $settings.hfToken)
            .textFieldStyle(.roundedBorder)

        Link("Get a token at huggingface.co",
             destination: URL(string: "https://huggingface.co/settings/tokens")!)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    Text(settings.diarizationEngine == .builtIn
        ? "No account needed. Models downloaded on first use (~95 MB)."
        : "Requires a HuggingFace token for pyannote speaker diarization.")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

**Step 2: Verify it compiles**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`
Expected: Build succeeds.

**Step 3: Commit**

```bash
git add Sources/Settings/SettingsView.swift
git commit -m "feat: add diarization engine picker in settings UI"
```

---

### Task 4: Add Diarization Model Downloads to ModelManager

**Files:**
- Modify: `Sources/Whisper/ModelManager.swift`

**Step 1: Add diarization model definitions and download methods**

In `Sources/Whisper/ModelManager.swift`, add after the existing `isModelDownloaded` method (after line 47):

```swift
// MARK: - Diarization models

enum DiarizationModel: String {
    case titanet = "titanet-large"
    case sileroVAD = "silero-vad-v6"

    var filename: String {
        switch self {
        case .titanet: "3dspeaker_speech_eres2net_large_sv_zh-cn_3dspeaker_16k.onnx"
        case .sileroVAD: "silero_vad.onnx"
        }
    }

    var downloadURL: URL {
        switch self {
        case .titanet:
            URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/3dspeaker_speech_eres2net_large_sv_zh-cn_3dspeaker_16k.onnx")!
        case .sileroVAD:
            URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx")!
        }
    }

    var displayName: String {
        switch self {
        case .titanet: "Speaker embedding model (~90 MB)"
        case .sileroVAD: "Voice activity detection model (~2 MB)"
        }
    }
}

func ensureDiarizationModel(_ model: DiarizationModel, progressCallback: (@Sendable (Double) -> Void)? = nil) async throws -> String {
    let path = diarizationModelPath(for: model)

    if FileManager.default.fileExists(atPath: path) {
        Log.whisper.info("Diarization model already cached: \(path)")
        progressCallback?(1.0)
        return path
    }

    let dir = modelsDirectory
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

    let url = model.downloadURL
    Log.whisper.info("Downloading diarization model from \(url.absoluteString)")

    let delegate = DownloadDelegate(progressCallback: progressCallback)
    let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    let (tempURL, response) = try await session.download(from: url, delegate: delegate)

    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw ModelManagerError.downloadFailed(model.rawValue)
    }

    try FileManager.default.moveItem(atPath: tempURL.path, toPath: path)
    Log.whisper.info("Diarization model downloaded to \(path)")
    return path
}

func diarizationModelPath(for model: DiarizationModel) -> String {
    modelsDirectory + "/\(model.filename)"
}

func isDiarizationModelDownloaded(_ model: DiarizationModel) -> Bool {
    FileManager.default.fileExists(atPath: diarizationModelPath(for: model))
}
```

Note: The exact download URLs above are from sherpa-onnx GitHub releases. The speaker embedding model uses 3D-Speaker ERes2Net (which has a permissive license and is available on sherpa-onnx releases). Verify the exact URLs are reachable at implementation time by checking https://github.com/k2-fsa/sherpa-onnx/releases/tag/speaker-recongition-models and https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models. Adjust filenames and URLs as needed.

**Step 2: Verify it compiles**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`
Expected: Build succeeds.

**Step 3: Commit**

```bash
git add Sources/Whisper/ModelManager.swift
git commit -m "feat: add diarization model download support to ModelManager"
```

---

### Task 5: Create SherpaOnnxDiarizer

**Files:**
- Create: `Sources/Meeting/SherpaOnnxDiarizer.swift`

This is the core new component. It wraps sherpa-onnx's C API to perform offline speaker diarization on a WAV file.

**Step 1: Create the diarizer actor**

Create `Sources/Meeting/SherpaOnnxDiarizer.swift`:

```swift
import CSherpaOnnx
import Foundation
import OSLog

/// A speaker segment with start/end time and speaker label.
struct SpeakerSegment {
    let start: Double
    let end: Double
    let speaker: String
}

/// Native speaker diarization using sherpa-onnx (TitaNet embeddings + spectral clustering).
actor SherpaOnnxDiarizer {
    static let shared = SherpaOnnxDiarizer()

    /// Run offline speaker diarization on a WAV file.
    /// Returns time-aligned speaker segments.
    func diarize(wavPath: String, embeddingModelPath: String, vadModelPath: String) throws -> [SpeakerSegment] {
        // Configure offline speaker diarization
        var config = SherpaOnnxOfflineSpeakerDiarizationConfig()

        // Segmentation (VAD-based)
        var segmentationConfig = SherpaOnnxOfflineSpeakerSegmentationModelConfig()
        // Note: sherpa-onnx's diarization uses a segmentation model, not raw VAD.
        // The VAD model path may need to be a pyannote-style segmentation ONNX.
        // If sherpa-onnx exposes a VAD-based segmentation path, use that instead.
        // Check sherpa-onnx C API docs for the correct config fields at implementation time.

        // Embedding
        var embeddingConfig = SherpaOnnxSpeakerEmbeddingExtractorConfig()
        embeddingModelPath.withCString { cStr in
            embeddingConfig.model = cStr
        }

        // Clustering
        var clusteringConfig = SherpaOnnxFastClusteringConfig()
        clusteringConfig.num_clusters = 0  // auto-detect
        clusteringConfig.threshold = 0.5   // cosine similarity threshold

        config.embedding = embeddingConfig
        config.clustering = clusteringConfig
        config.min_duration_on = 0.3
        config.min_duration_off = 0.5

        // Create diarization instance
        guard let diarizer = SherpaOnnxCreateOfflineSpeakerDiarization(&config) else {
            throw DiarizationError.initFailed("Failed to create sherpa-onnx diarizer")
        }
        defer { SherpaOnnxDestroyOfflineSpeakerDiarization(diarizer) }

        // Process the WAV file
        // Read WAV samples (16kHz mono float32)
        let samples = try readWAVSamples(path: wavPath)

        guard let result = SherpaOnnxOfflineSpeakerDiarizationProcess(diarizer, samples, Int32(samples.count)) else {
            throw DiarizationError.processFailed("Diarization returned no result")
        }
        defer { SherpaOnnxOfflineSpeakerDiarizationDestroyResult(result) }

        // Extract segments
        let numSegments = SherpaOnnxOfflineSpeakerDiarizationResultGetNumSegments(result)
        var segments: [SpeakerSegment] = []

        for i in 0..<numSegments {
            let seg = SherpaOnnxOfflineSpeakerDiarizationResultGetSegment(result, i)
            let speaker = String(format: "SPEAKER_%02d", seg.speaker)
            segments.append(SpeakerSegment(
                start: Double(seg.start),
                end: Double(seg.end),
                speaker: speaker
            ))
        }

        Log.meeting.info("Diarization complete: \(segments.count) segments, \(Set(segments.map(\.speaker)).count) speakers")
        return segments
    }

    /// Read a 16kHz mono WAV file into Float32 samples.
    private func readWAVSamples(path: String) throws -> [Float] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        // WAV header is 44 bytes for standard PCM
        // MyWhispers records IEEE Float32, 16kHz, mono
        guard data.count > 44 else {
            throw DiarizationError.invalidWAV("WAV file too small")
        }
        let sampleData = data.dropFirst(44)
        let count = sampleData.count / MemoryLayout<Float>.size
        return sampleData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self).prefix(count))
        }
    }
}

enum DiarizationError: LocalizedError {
    case initFailed(String)
    case processFailed(String)
    case invalidWAV(String)
    case modelsNotDownloaded

    var errorDescription: String? {
        switch self {
        case .initFailed(let detail): "Diarization initialization failed: \(detail)"
        case .processFailed(let detail): "Diarization failed: \(detail)"
        case .invalidWAV(let detail): "Invalid WAV file: \(detail)"
        case .modelsNotDownloaded: "Diarization models not downloaded. They will be downloaded on first use."
        }
    }
}
```

**Important implementation note:** The exact sherpa-onnx C API struct names and function signatures above are approximate. At implementation time, refer to the actual `sherpa-onnx-c-api.h` header that was copied in Task 1. The API may use slightly different struct/function names. The key functions to look for in the header are:
- `SherpaOnnxCreateOfflineSpeakerDiarization`
- `SherpaOnnxOfflineSpeakerDiarizationProcess`
- Result iteration functions

**Step 2: Verify it compiles**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`
Expected: Build succeeds (may need to adjust C API calls to match actual header).

**Step 3: Commit**

```bash
git add Sources/Meeting/SherpaOnnxDiarizer.swift
git commit -m "feat: add SherpaOnnxDiarizer for native speaker diarization"
```

---

### Task 6: Add Transcript Merge Logic

**Files:**
- Create: `Sources/Meeting/TranscriptMerger.swift`

This merges whisper.cpp transcription segments with sherpa-onnx diarization speaker labels by timestamp overlap.

**Step 1: Create the merger**

Create `Sources/Meeting/TranscriptMerger.swift`:

```swift
import Foundation

/// Merges whisper.cpp transcription segments with speaker diarization labels.
enum TranscriptMerger {
    /// A transcription segment with text, timestamps, and optional speaker.
    struct MergedSegment {
        let start: Double
        let end: Double
        let text: String
        let speaker: String
    }

    /// Assign speaker labels to transcription segments by finding the diarization
    /// segment with the greatest time overlap for each transcription segment.
    static func merge(
        transcriptionSegments: [(start: Double, end: Double, text: String)],
        speakerSegments: [SpeakerSegment]
    ) -> [MergedSegment] {
        transcriptionSegments.map { tseg in
            let speaker = bestOverlappingSpeaker(
                start: tseg.start,
                end: tseg.end,
                speakerSegments: speakerSegments
            )
            return MergedSegment(
                start: tseg.start,
                end: tseg.end,
                text: tseg.text,
                speaker: speaker
            )
        }
    }

    /// Find the speaker segment with the greatest overlap for a given time range.
    /// Returns "UNKNOWN" if no overlap found.
    private static func bestOverlappingSpeaker(
        start: Double,
        end: Double,
        speakerSegments: [SpeakerSegment]
    ) -> String {
        var bestSpeaker = "UNKNOWN"
        var bestOverlap: Double = 0

        for seg in speakerSegments {
            let overlapStart = max(start, seg.start)
            let overlapEnd = min(end, seg.end)
            let overlap = max(0, overlapEnd - overlapStart)

            if overlap > bestOverlap {
                bestOverlap = overlap
                bestSpeaker = seg.speaker
            }
        }

        return bestSpeaker
    }
}
```

**Step 2: Verify it compiles**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`
Expected: Build succeeds.

**Step 3: Commit**

```bash
git add Sources/Meeting/TranscriptMerger.swift
git commit -m "feat: add TranscriptMerger for aligning speakers with transcription"
```

---

### Task 7: Add Native Transcription Pipeline to MeetingRecorder

**Files:**
- Modify: `Sources/Meeting/MeetingRecorder.swift`

This adds the built-in diarization path alongside the existing WhisperX path.

**Step 1: Add the native transcription method**

In `Sources/Meeting/MeetingRecorder.swift`, add a new method after the existing `transcribe` method (after line 139):

```swift
/// Transcribe using whisper.cpp + sherpa-onnx native diarization.
func transcribeBuiltIn(wavURL: URL) async throws -> String {
    // 1. Ensure diarization models are downloaded
    let embeddingPath = try await ModelManager.shared.ensureDiarizationModel(.titanet)
    let vadPath = try await ModelManager.shared.ensureDiarizationModel(.sileroVAD)

    // 2. Transcribe with whisper.cpp
    let model = settingsStore.selectedModel
    let language = settingsStore.selectedLanguage
    let modelPath = try await ModelManager.shared.ensureModel(model)

    let engine = WhisperCppEngine.shared
    try await engine.loadModel(path: modelPath)

    let audioData = try Data(contentsOf: wavURL)
    // Skip 44-byte WAV header, convert to [Float]
    let sampleData = audioData.dropFirst(44)
    let samples: [Float] = sampleData.withUnsafeBytes { buffer in
        Array(buffer.bindMemory(to: Float.self))
    }

    let transcriptionSegments = try await engine.transcribeWithSegments(
        samples: samples,
        language: language == .auto ? nil : language.rawValue
    )

    // 3. Run sherpa-onnx diarization
    let speakerSegments = try await SherpaOnnxDiarizer.shared.diarize(
        wavPath: wavURL.path,
        embeddingModelPath: embeddingPath,
        vadModelPath: vadPath
    )

    // 4. Merge transcription with speaker labels
    let merged = TranscriptMerger.merge(
        transcriptionSegments: transcriptionSegments,
        speakerSegments: speakerSegments
    )

    // 5. Format as Markdown
    let markdown = formatMergedAsMarkdown(segments: merged, startDate: recordingStartDate ?? Date())

    // 6. Clean up WAV
    try? FileManager.default.removeItem(at: wavURL)

    return markdown
}

private func formatMergedAsMarkdown(segments: [TranscriptMerger.MergedSegment], startDate: Date) -> String {
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

    for segment in segments {
        if segment.speaker == currentSpeaker {
            currentText += " " + segment.text.trimmingCharacters(in: .whitespaces)
        } else {
            if let prev = currentSpeaker {
                md += "**\(prev)** (\(formatTimestamp(currentStart)))\n"
                md += "\(currentText.trimmingCharacters(in: .whitespaces))\n\n"
            }
            currentSpeaker = segment.speaker
            currentText = segment.text.trimmingCharacters(in: .whitespaces)
            currentStart = segment.start
        }
    }

    if let prev = currentSpeaker {
        md += "**\(prev)** (\(formatTimestamp(currentStart)))\n"
        md += "\(currentText.trimmingCharacters(in: .whitespaces))\n"
    }

    return md
}
```

**Step 2: Add `transcribeWithSegments` to WhisperCppEngine**

This method needs to exist on `WhisperCppEngine` to return segments with timestamps (not just text). Check the existing `transcribe` method in `Sources/Whisper/WhisperCppEngine.swift` and add a variant that returns `[(start: Double, end: Double, text: String)]` by iterating `whisper_full_n_segments` and calling `whisper_full_get_segment_t0`, `whisper_full_get_segment_t1`, `whisper_full_get_segment_text` from the whisper.cpp C API.

**Step 3: Verify it compiles**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`
Expected: Build succeeds.

**Step 4: Commit**

```bash
git add Sources/Meeting/MeetingRecorder.swift Sources/Whisper/WhisperCppEngine.swift
git commit -m "feat: add native transcription pipeline with built-in diarization"
```

---

### Task 8: Wire DiarizationEngine Switch in AppState

**Files:**
- Modify: `Sources/App/AppState.swift`

**Step 1: Route meeting transcription based on engine setting**

Find the method that calls `meetingRecorder.transcribe(wavURL:)` in AppState.swift and update it to check the diarization engine:

```swift
// Replace the direct call to meetingRecorder.transcribe(wavURL:) with:
let transcript: String
switch settingsStore.diarizationEngine {
case .builtIn:
    transcript = try await meetingRecorder.transcribeBuiltIn(wavURL: wavURL)
case .whisperX:
    transcript = try await meetingRecorder.transcribe(wavURL: wavURL)
}
```

For the `.builtIn` case, the HF token check is no longer needed (it's only in the existing `transcribe` method).

**Step 2: Verify it compiles**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`
Expected: Build succeeds.

**Step 3: Commit**

```bash
git add Sources/App/AppState.swift
git commit -m "feat: wire diarization engine switch in meeting transcription flow"
```

---

### Task 9: End-to-End Manual Testing

**Step 1: Build and run the app**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build && swift run`

**Step 2: Test Built-in engine (default)**

1. Open Settings — verify "Diarization" picker shows "Built-in (TitaNet)" selected by default
2. Verify HF token field is hidden
3. Start a meeting recording (play audio with 2+ speakers if possible, or just test with single voice)
4. Stop recording — verify models download on first use with progress indication
5. Verify transcript is generated with `SPEAKER_XX` labels
6. Verify transcript saved to configured directory

**Step 3: Test WhisperX engine**

1. Switch to "WhisperX (pyannote)" in Settings
2. Verify HF token field appears
3. Enter a valid token
4. Record and transcribe — verify existing WhisperX pipeline still works

**Step 4: Test edge cases**

- Switch engines between recordings (should work)
- Start transcription with Built-in when models not yet downloaded (should auto-download)
- Cancel during model download (should handle gracefully)

**Step 5: Commit any fixes from testing**

```bash
git add -A
git commit -m "fix: adjustments from end-to-end testing"
```
