# Streaming Transcription with whisper.cpp — Design

**Date:** 2026-03-13
**Status:** Approved

## Goal

Replace WhisperKit with whisper.cpp to enable real-time streaming transcription in MyWhispers. Inspired by [SimulStreaming](https://github.com/ufal/SimulStreaming)'s LocalAgreement approach: type only text that stabilizes across consecutive inferences.

## Context

MyWhispers is a macOS menu bar app for speech-to-text. The current engine (WhisperKit) uses CoreML and only supports batch transcription. SimulStreaming's AlignAtt policy requires PyTorch model internals (attention hooks) that CoreML doesn't expose. However, whisper.cpp provides full C API access, Metal GPU acceleration, and its `stream.cpp` example demonstrates a proven sliding-window approach. By switching to whisper.cpp, we get both batch and streaming modes with a single engine.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  MyWhispers macOS App                                   │
│                                                         │
│  AppState (@Observable, @MainActor)                     │
│  ├── AudioCapture (AVAudioEngine, 16kHz Float32 PCM)    │
│  ├── WhisperCppEngine (actor, C interop)                │
│  │   └── whisper.cpp (vendored C library, Metal GPU)    │
│  ├── ModelManager (actor, GGML download/cache)          │
│  ├── TextInjector (CGEvent keystroke simulation)         │
│  └── RecordingIndicator (NSPanel at text cursor)        │
│                                                         │
│  SettingsStore + SettingsView                            │
│  (model, language, hotkey, streaming toggle, launch)    │
└─────────────────────────────────────────────────────────┘
```

### Key Changes from Current Architecture

| Component | Before (WhisperKit) | After (whisper.cpp) |
|-----------|-------------------|-------------------|
| Engine | `WhisperEngine` (WhisperKit actor) | `WhisperCppEngine` (C interop actor) |
| Model format | CoreML (HuggingFace WhisperKit) | GGML (HuggingFace ggerganov) |
| GPU | CoreML/ANE | Metal (flash attention) |
| Streaming | Not possible | Sliding-window with LocalAgreement |
| Model download | WhisperKit built-in | Custom `ModelManager` actor |
| Package dep | `argmaxinc/WhisperKit` | Vendored C target |

**Unchanged:** AudioCapture, TextInjector, RecordingIndicator, KeyboardShortcuts, SettingsStore (structure), hotkey flow.

## Streaming Algorithm

### Sliding Window with Word-Level LocalAgreement

```
Audio timeline (step=3s, window=10s, keep=200ms):

|----keep----|------------------new step-------------------|
|<- 200ms  ->|<-              3000ms step               ->|
|<-                    10000ms window                    ->|

Iter 1: [=======window=======] → "Hello world how"
Iter 2: ---[=======window=======] → "Hello world how are"
         Stable: ["Hello","world","how"] (agreed) → TYPE "Hello world how"
Iter 3: ------[=======window=======] → "Hello world how are you"
         Stable: ["are"] (new agreement) → TYPE " are"
...
On stop: Final full inference → TYPE remaining text
```

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `stepMs` | 3000 | Inference interval (ms) |
| `lengthMs` | 10000 | Max audio window size (ms) |
| `keepMs` | 200 | Overlap from previous window (ms) |
| `stabilityThreshold` | 2 | Consecutive agreements before typing |

### Algorithm

```
typedWordCount = 0
previousWords = []
promptTokens = []

while recording:
    sleep(stepMs)
    window = audioCapture.getWindow(lengthMs, keepMs)
    if window is too short: continue

    (text, tokens) = whisperCpp.transcribeWindow(
        samples: window,
        language: language,
        promptTokens: promptTokens
    )
    currentWords = splitIntoWords(stripSpecialTokens(text))

    // Word-level LocalAgreement: longest common word prefix
    stableCount = longestCommonWordPrefix(currentWords, previousWords)
    previousWords = currentWords

    // Type only newly confirmed words
    if stableCount > typedWordCount:
        newText = joinWords(currentWords[typedWordCount..<stableCount])
        TextInjector.typeText(newText)
        typedWordCount = stableCount

    // Feed confirmed tokens as prompt context for next iteration
    promptTokens = tokens (from confirmed segments)

on stop:
    finalText = whisperCpp.transcribe(allAudio, language, promptTokens)
    finalWords = splitIntoWords(finalText)
    if finalWords.count > typedWordCount:
        remaining = joinWords(finalWords[typedWordCount...])
        TextInjector.typeText(remaining)
    else if typedWordCount == 0 && !finalText.isEmpty:
        TextInjector.typeText(finalText)  // fallback
```

### Improvements Over Basic Sliding Window

1. **Word-level agreement** — compares words, not characters. Avoids mid-word splits.
2. **Prompt context** — feeds previous segment tokens as `prompt_tokens` to `whisper_full()`, improving cross-chunk coherence (from whisper.cpp's stream example).
3. **Audio overlap** (`keepMs`) — keeps 200ms from previous window to prevent word boundary truncation.
4. **Special token stripping** — removes `<|...|>` Whisper control tokens from output.

## Component Details

### WhisperCppEngine

```swift
actor WhisperCppEngine {
    private var ctx: OpaquePointer?  // whisper_context*

    // Model lifecycle
    func loadModel(path: String) throws  // whisper_init_from_file_with_params
    func unloadModel()                   // whisper_free
    var isLoaded: Bool

    // Batch transcription
    func transcribe(samples: [Float], language: String) -> String

    // Streaming window transcription (returns text + tokens for prompt context)
    func transcribeWindow(samples: [Float], language: String,
                          promptTokens: [Int32]) -> (text: String, tokens: [Int32])
}
```

C API usage:
- `whisper_init_from_file_with_params()` with `use_gpu = true`, `flash_attn = true`
- `whisper_full()` with `WHISPER_SAMPLING_GREEDY`, `single_segment = true` (for streaming windows)
- `whisper_full_n_segments()` / `whisper_full_get_segment_text()` to read results
- `whisper_full_get_token_id()` to extract tokens for prompt context feeding

### ModelManager

```swift
actor ModelManager {
    func downloadModel(_ model: WhisperModel) async throws -> URL
    func modelPath(for model: WhisperModel) -> URL?
    func isModelDownloaded(_ model: WhisperModel) -> Bool
    var downloadProgress: Double
}
```

Downloads from: `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-{model}.bin`
Cache location: `~/Library/Application Support/MyWhispers/models/`
Available models: tiny, base, small, medium, large-v3

### AudioCapture additions

```swift
/// Get the last `lengthMs` of audio with `keepMs` overlap from previous window.
func getWindow(lengthMs: Int, keepMs: Int) -> [Float]
```

Existing methods unchanged: `startRecording()`, `stopRecording()`, `peekSamples()`.

### Package.swift

```swift
dependencies: [
    // Remove: .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
    .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
],
targets: [
    .target(
        name: "whisper_cpp",
        path: "Vendor/whisper.cpp",
        exclude: ["examples", "tests", "bindings", "models", "samples"],
        sources: ["src/whisper.cpp", "ggml/src/..."],
        publicHeadersPath: "include",
        cSettings: [
            .define("GGML_USE_METAL"),
            .define("ACCELERATE"),
        ],
        linkerSettings: [
            .linkedFramework("Metal"),
            .linkedFramework("MetalKit"),
            .linkedFramework("Accelerate"),
        ]
    ),
    .executableTarget(
        name: "MyWhispers",
        dependencies: ["whisper_cpp", "KeyboardShortcuts"],
        ...
    ),
]
```

### Settings

- **Model picker** — GGML models (tiny, base, small, medium, large-v3)
- **Language picker** — unchanged
- **Streaming toggle** — `Enable streaming mode` (default: off)
  - OFF: batch mode (record → transcribe on release)
  - ON: sliding-window streaming (type progressively, finalize on release)
- **Hotkey, Launch at login** — unchanged
- **Removed:** Baseten API key, Baseten model ID (no longer needed)

## Migration Plan

1. Add whisper.cpp as git submodule in `Vendor/whisper.cpp/`
2. Configure C library target in Package.swift with Metal support
3. Build `WhisperCppEngine` actor (Swift ↔ C interop wrapper)
4. Build `ModelManager` actor (GGML download from HuggingFace)
5. Update `WhisperModels` enum for GGML model names
6. Update `AppState` — batch mode using `WhisperCppEngine`
7. Add streaming mode to `AppState` (sliding-window + LocalAgreement)
8. Update `SettingsStore` (remove Baseten fields, keep streaming toggle)
9. Update `SettingsView` (remove Baseten UI, update model names)
10. Remove WhisperKit dependency from Package.swift
11. Test batch mode (regression)
12. Test streaming mode (progressive typing)

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| whisper.cpp build complexity with SPM | Start with minimal source files, add incrementally |
| Metal shader compilation issues | Test on target hardware early |
| Model download reliability | Retry logic, progress UI, graceful error handling |
| Streaming latency on large models | Default to `small` model, document model size tradeoffs |
| Word boundary glitches | keepMs overlap + word-level agreement (not char-level) |
