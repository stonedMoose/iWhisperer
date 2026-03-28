# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dual-platform local speech-to-text app powered by whisper.cpp (OpenAI Whisper) with Metal GPU acceleration:
- **MacWhisperer** — macOS 14+ menu bar app (SPM, in `Whisperer/` directory)
- **iWhisperer** — iOS 17+ app (xcodegen + Xcode)

Both share the same whisper.cpp C FFI layer but have separate codebases.

## Build Commands

See README.md for prerequisites and full setup. Quick reference:

```bash
# One-time: compile whisper.cpp
cd Whisperer && bash scripts/build-whisper.sh      # macOS
cd iWhisperer && bash Scripts/build-whisper-ios.sh  # iOS

# Build & run
pnpm run launch:mac         # swift run MacWhisperer
pnpm run launch:ios         # xcodegen + build + open Xcode

# Distribution
pnpm run distribute:mac     # Fastlane: build + DMG
pnpm run release:mac        # Fastlane: build + notarize + DMG + GitHub release
```

No test targets exist yet.

## Architecture

### C FFI Layer
Both apps import whisper.cpp via a C module map (`Vendor/CWhisper/`). The static libraries live in `Vendor/whisper-built/` (git-ignored, built by scripts). macOS additionally uses sherpa-onnx for speaker diarization (`Vendor/CSherpaOnnx/`).

### Shared Concepts (separate implementations per platform)
- **WhisperCppEngine** (actor) — loads whisper model, runs inference via C API with `OpaquePointer`
- **ModelManager** (.shared singleton) — downloads/manages Whisper models on demand
- **AudioCapture** — AVAudioEngine at 16kHz Float32
- **WhisperModels** — model catalog (base, small, medium, large)

### macOS-specific (`Whisperer/Sources/`)
- **AppState** (@Observable) — central state: recording, transcription, permissions
- **MenuBarExtra** SwiftUI + **NSPanel** for floating recording indicator
- **TextInjector** — CGEvent-based keyboard simulation to paste transcription into any field
- **MeetingRecorder** + **SherpaOnnxDiarizer** + **TranscriptMerger** — multi-speaker meeting mode
- **LLMProvider** + **TranscriptRefiner** — external API post-processing
- **KeyboardShortcuts** (SPM dependency) — global hotkey
- **Localization** — `L10n.swift` / `AppLanguage.swift`

### iOS-specific (`iWhisperer/Sources/`)
- **TranscriptionEngine** (@Observable) — state machine for recording lifecycle + model loading
- **TabView** UI: Record, History, Settings
- **SwiftData** model: `Transcription` (persisted history)
- **Live Activity** + Dynamic Island (`iWhispererWidgetExtension/`)
- **App Intents** + Siri Shortcuts (`ToggleRecordingIntent`)
- **OnboardingView** — first-launch permission flow

### State Management
Both apps use `@Observable` (Swift 5.9+) with `@AppStorage`-backed `SettingsStore`.

### Concurrency
Swift async/await with actors (`WhisperCppEngine`). Recording runs in background `Task`s.

## Key Conventions
- Bundle ID: `fr.moose.Whisperer` (macOS), `com.julienlhermite.iWhisperer` (iOS)
- Logging via custom `Log` struct (os.Logger wrapper)
- Design docs in `docs/plans/` — some reference old paths (`MyWhispers/`, `MyWhispersIOS/`) before the rename to `iWhisperer`
