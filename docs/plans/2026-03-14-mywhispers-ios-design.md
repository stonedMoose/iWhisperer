# MyWhispers iOS — Design Document

**Date**: 2026-03-14
**Status**: Approved

## Overview

Standalone iOS app for quick voice-to-text dictation using local Whisper models. Action Button triggers recording, Live Activity shows status, text auto-copies to clipboard. Includes transcription history.

**Target**: iOS 17+ / iPhone 15 Pro+ (A17 Pro)

## Architecture

Single-target iOS app (Swift, SwiftUI).

```
MyWhispersIOS/
├── App/                  # App entry point, lifecycle
├── Audio/                # AudioCapture (AVAudioEngine, 16kHz mono)
├── Whisper/              # WhisperCppEngine (C interop), ModelManager
├── Intents/              # AppIntent for Action Button trigger
├── LiveActivity/         # ActivityKit Live Activity + Dynamic Island
├── History/              # SwiftData models + list UI
├── Settings/             # Model picker, language, storage management
└── CWhisper/             # whisper.cpp system library
```

### Key Actors

- `TranscriptionEngine` (@MainActor, @Observable) — state machine: idle → recording → transcribing → done
- `WhisperCppEngine` — wraps whisper.cpp C API (ported from macOS)
- `ModelManager` — downloads/caches GGML models to app documents
- `AudioCapture` — AVAudioEngine recording at 16kHz mono

## User Flow

1. **Setup** (first launch): pick Whisper model, download it, select language
2. **Record**: press Action Button → app launches in background, starts recording, Live Activity appears (Dynamic Island shows waveform/duration)
3. **Stop**: press Action Button again → recording stops, transcription begins, Dynamic Island shows progress
4. **Done**: text auto-copied to clipboard, notification with preview, Live Activity ends. Haptic feedback confirms.
5. **History**: open app → see list of past transcriptions (date, preview, full text). Tap to copy, swipe to delete.

## Data Model (SwiftData)

```swift
@Model
class Transcription {
    var text: String
    var language: String
    var model: String
    var duration: TimeInterval   // audio duration
    var createdAt: Date
}
```

## Action Button Integration

Uses `AppIntent` registered as a system action:
- `StartRecordingIntent` — toggles recording on/off
- Registered via `AppShortcutsProvider` so it appears in Action Button settings

## Live Activity

- **Compact** (Dynamic Island): mic icon + elapsed time
- **Expanded**: elapsed time + "Recording..." / "Transcribing..." status
- **Lock Screen**: same as expanded + cancel button

## Settings

- **Whisper Model**: picker (tiny, base, small) with download size. Default: base.
- **Language**: auto-detect or manual (13 languages)
- **Auto-copy**: toggle, on by default
- **Storage**: downloaded models with sizes, delete button per model

No API keys needed — fully local.

## Model Management

- Models downloaded from HuggingFace on demand (same GGML URLs as macOS)
- Stored in app's Documents directory
- Download progress shown inline in settings
- Supported models: tiny (~75MB), base (~142MB), small (~466MB)
- large-v3 excluded (~3GB, too heavy for mobile)

## Error Handling

- No model downloaded: first launch guides user to download before Action Button works
- Microphone permission denied: prompt with Settings deep link
- Recording interrupted (phone call): save partial audio, transcribe what we have
- Model loading fails (memory pressure): fall back to smaller model or show error

## Out of Scope

- Meeting mode / speaker diarization
- Streaming transcription (batch only)
- LLM refinement
- Custom keyboard extension
- iPad support
- Shortcuts integration (future enhancement)
