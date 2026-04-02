# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Workflow Rule — Always Deploy After Changes

After completing **any user-requested modification** to the macOS app, always run:

```bash
pnpm run deploy:mac
```

This single command rebuilds in release mode, copies the binary to `/Applications/MacWhisperer.app`, re-signs it, and relaunches the app. Do this automatically — do not wait for the user to ask.

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
pnpm run launch:mac         # swift run MacWhisperer (debug)
pnpm run deploy:mac         # release build + codesign + replace /Applications + relaunch
pnpm run launch:ios         # xcodegen + build + open Xcode

# Distribution
pnpm run distribute:mac     # Fastlane: build + DMG
pnpm run release:mac        # Fastlane: build + notarize + DMG + GitHub release
```

Signing credentials live in `Whisperer/.env` (gitignored). Copy `.env.example` to get started.

No test targets exist yet.

## Architecture

### C FFI Layer
Both apps import whisper.cpp via a C module map (`Vendor/CWhisper/`). The static libraries live in `Vendor/whisper-built/` (git-ignored, built by scripts). macOS additionally uses sherpa-onnx for speaker diarization (`Vendor/CSherpaOnnx/`).

### Shared Concepts (separate implementations per platform)
- **WhisperCppEngine** (actor) — loads whisper model, runs inference via C API with `OpaquePointer`
- **ModelManager** (.shared singleton) — downloads/manages Whisper models on demand
- **AudioCapture** — AVAudioEngine at 16kHz Float32; uses serial `DispatchQueue` (not actor) because AVAudioEngine tap closures are synchronous
- **WhisperModels** — model catalog (base, small, medium, large)

### macOS-specific (`Whisperer/Sources/`)
- **AppState** (@Observable) — central state: recording, transcription, permissions
- **MenuBarExtra** SwiftUI + **NSPanel** for floating recording indicator
- **MenuBarIconState** — renders flag pattern through waveform SF Symbol using `sourceAtop` compositing; `language` property triggers redraw
- **FlagPattern** — defined in `WhisperModels.swift` alongside `WhisperLanguage`; each language has a `flagPattern: FlagPattern?`
- **RecordingIndicator** — NSPanel positioned near text cursor; uses AX caret first, then last-click (validated within 300pt), then mouse fallback; installs global `leftMouseDown` monitor via `installClickMonitor()`
- **TextInjector** — CGEvent-based keyboard simulation to paste transcription into any field
- **MeetingRecorder** + **SherpaOnnxDiarizer** + **TranscriptMerger** — multi-speaker meeting mode
- **LLMProvider** + **TranscriptRefiner** — external API post-processing (OpenAI, Anthropic, Claude CLI)
- **KeyboardShortcuts** (SPM dependency) — global hotkeys: `holdToRecord`, `meetingRecord`, `cycleLanguage`
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
- Logging via custom `Log` struct (os.Logger wrapper) — members: `audio`, `whisper`, `permissions`, `general`, `ui`, `meeting`
- Design docs in `docs/plans/` — some reference old paths (`MyWhispers/`, `MyWhispersIOS/`) before the rename to `iWhisperer`
- Direct distribution only (no App Store) — sandbox disabled in `MacWhisperer.entitlements` to allow CGEvent injection and Carbon hotkeys

## Known Constraints

### Sandbox
Do NOT enable `com.apple.security.app-sandbox = true` in `MacWhisperer.entitlements` (direct distribution build). Carbon `RegisterEventHotKey` and `CGEventPost` are blocked by sandbox without additional Apple-approved entitlements. The App Store entitlements file (`MacWhisperer.appstore.entitlements`) has sandbox enabled for that distribution channel only.

### AudioCapture thread safety
`AudioCapture` is `@unchecked Sendable` with a serial `bufferQueue` DispatchQueue. It cannot use Swift actors because AVAudioEngine's tap closure is synchronous and cannot `await` into an actor.

### CF bridged type casts
`as! AXUIElement` and `as! AXValue` in `RecordingIndicator.swift` are safe — CF bridged types always succeed on `as!` per the Swift compiler. Using `as?` would trigger a warning.
