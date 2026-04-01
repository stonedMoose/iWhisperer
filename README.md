# Whisperer

**[Website](https://stonedmoose.github.io/iWhisperer/)** | **[Download](https://github.com/stonedMoose/iWhisperer/releases)**

Local, private speech-to-text for Apple platforms — powered by [whisper.cpp](https://github.com/ggerganov/whisper.cpp) with Metal GPU acceleration. No cloud required for transcription.

| | MacWhisperer | iWhisperer |
|---|---|---|
| **Platform** | macOS 14+ | iOS 17+ |
| **UI** | Menu bar app | Full-screen SwiftUI |
| **Build** | Swift Package Manager | xcodegen + Xcode |
| **Transcription** | Batch + streaming modes | Batch mode |
| **Special features** | Meeting recording with speaker diarization, LLM transcript refinement, global hotkeys (record + cycle language), language flag icon, text injection at cursor | Transcription history (SwiftData), Live Activity, Siri Shortcuts, Action Button |

## Prerequisites

- **Xcode 15+**
- **CMake** — `brew install cmake`
- **xcodegen** (iOS only) — `brew install xcodegen`

## Quick Start

### macOS — MacWhisperer

```bash
# 1. Build whisper.cpp native libraries (one-time)
cd Whisperer && bash scripts/build-whisper.sh

# 2. Build & run
swift build && swift run MacWhisperer
```

### iOS — iWhisperer

```bash
# 1. Build whisper.cpp for iOS arm64 (one-time)
cd iWhisperer && bash Scripts/build-whisper-ios.sh

# 2. Generate Xcode project & build
xcodegen generate
open iWhisperer.xcodeproj
```

## pnpm Scripts

All commands are available from the repo root via `pnpm run`:

| Command | Description |
|---------|-------------|
| `build:mac` | Debug build (swift build) |
| `deploy:mac` | Release build + replace binary + codesign + relaunch |
| `launch:mac` | Build & run MacWhisperer (debug) |
| `bundle:mac` | Signed .app bundle (release) |
| `distribute:mac` | Build + DMG via Fastlane |
| `release:mac` | Full release: build + notarize + DMG + GitHub release |
| `build:ios` | Generate Xcode project + build |
| `launch:ios` | Build + open in Xcode |
| `kill:mac` / `kill:ios` | Terminate running app |

## Repository Structure

```
.
├── Whisperer/                  # macOS app (MacWhisperer)
│   ├── Sources/
│   │   ├── App/                # AppState, entry point, logging
│   │   ├── Audio/              # AVAudioEngine capture, WAV writer
│   │   ├── Whisper/            # WhisperCppEngine, ModelManager, model catalog
│   │   ├── Settings/           # SettingsStore, SettingsView
│   │   ├── UI/                 # Menu bar icon, recording indicator, setup
│   │   ├── Hotkey/             # Global keyboard shortcut handling
│   │   ├── TextInjection/      # CGEvent-based text insertion
│   │   ├── Meeting/            # Multi-speaker recording + diarization
│   │   ├── LLM/                # Transcript refinement (OpenAI, Anthropic, Claude CLI)
│   │   └── Localization/       # 6-language i18n (en, fr, es, zh, pt, de)
│   ├── Vendor/
│   │   ├── CWhisper/           # C module map for whisper.cpp FFI
│   │   ├── CSherpaOnnx/        # C module map for sherpa-onnx (diarization)
│   │   └── whisper.cpp/        # Git submodule
│   ├── scripts/                # build-whisper.sh, bundle.sh, distribute.sh
│   ├── fastlane/               # Fastlane config for distribution
│   ├── Package.swift           # SPM manifest
│   └── MacWhisperer.entitlements
│
├── iWhisperer/                 # iOS app
│   ├── Sources/
│   │   ├── App/                # TranscriptionEngine, onboarding, recording UI
│   │   ├── Audio/              # AVAudioEngine capture
│   │   ├── Whisper/            # WhisperCppEngine, ModelManager, model catalog
│   │   ├── Settings/           # SettingsView
│   │   ├── History/            # SwiftData transcription history
│   │   ├── Intents/            # Siri Shortcuts, Action Button
│   │   └── LiveActivity/       # Dynamic Island widget
│   ├── iWhispererWidgetExtension/  # Live Activity widget extension
│   ├── Vendor/CWhisper/        # C module map for whisper.cpp FFI
│   ├── Scripts/                # build-whisper-ios.sh
│   └── project.yml             # xcodegen config
│
├── docs/
│   ├── plans/                  # Design & implementation documents
│   └── export-compliance/      # BIS CCATS + ANSSI crypto declarations
│
├── package.json                # pnpm scripts for build/launch
├── Whisperer/.env.example      # Signing identity template (copy to .env, gitignored)
├── CLAUDE.md                   # Claude Code guidance
└── README.md
```

## How It Works

Both apps use the same core pipeline:

1. **Audio capture** — `AVAudioEngine` records at 16 kHz Float32
2. **Whisper inference** — whisper.cpp runs locally via Metal GPU, accessed through a Swift C FFI layer (`import CWhisper`)
3. **Output** — macOS injects text at the cursor via `CGEvent`; iOS copies to clipboard or stores in history

Whisper models are downloaded on demand to the app's Application Support directory. Supported models: base, small, medium, large.

### macOS Extras

- **Streaming mode** — sliding window transcription with word-level LocalAgreement for real-time text insertion
- **Meeting mode** — records full meetings, uses sherpa-onnx for speaker diarization, merges speaker-labeled segments
- **LLM refinement** — optionally post-processes meeting transcripts via OpenAI, Anthropic API, or Claude Code CLI
- **Language flag icon** — menu bar icon renders the active language as a simplified flag pattern composited through the waveform shape
- **Cycle language shortcut** — keyboard shortcut to cycle through preferred languages without opening Settings

## Distribution (macOS)

MacWhisperer is distributed directly (not via App Store) at [stonedmoose.github.io/iWhisperer](https://stonedmoose.github.io/iWhisperer/).

Signing credentials are stored in `Whisperer/.env` (gitignored). Copy `.env.example` and fill in your values.

```bash
# Development: build, sign, and relaunch instantly
pnpm run deploy:mac

# Quick distribution: build + DMG
pnpm run distribute:mac

# Full release: build + notarize + DMG + GitHub release draft
pnpm run release:mac
```

For notarization, place an [App Store Connect API key](https://docs.fastlane.tools/app-store-connect-api/) at `Whisperer/fastlane/api_key.json`.

> **Gatekeeper note:** Builds without notarization require right-click → Open on first launch.

## Permissions

### macOS
- **Microphone** — audio capture for transcription
- **Accessibility** — text injection at cursor position (CGEvent)

### iOS
- **Microphone** — audio capture for transcription

## License

This is an open-source personal project by [Julien Lhermite](mailto:m@lumpy.me).
