# MyWhispers — Design Document

## Summary

A macOS menu bar app that transcribes speech to text at the cursor position using OpenAI's Whisper model running locally via Apple's MLX framework. Hold a hotkey to record, release to transcribe and inject text.

**Target:** macOS 14+ (Apple Silicon only)
**Language:** Swift 5.9+ / SwiftUI
**Distribution:** Direct .app bundle (not sandboxed)

## Architecture

```
┌─────────────────────────────────────────────┐
│              MyWhispers.app                  │
│                                              │
│  ┌──────────┐  ┌───────────┐  ┌───────────┐ │
│  │ MenuBar  │  │  Settings  │  │  Hotkey   │ │
│  │ Manager  │  │  Window    │  │  Monitor  │ │
│  └──────────┘  └───────────┘  └─────┬─────┘ │
│                                     │        │
│                              ┌──────▼──────┐ │
│                              │   Audio     │ │
│                              │   Capture   │ │
│                              └──────┬──────┘ │
│                              ┌──────▼──────┐ │
│                              │  MLX Whisper│ │
│                              │  Engine     │ │
│                              └──────┬──────┘ │
│                              ┌──────▼──────┐ │
│                              │  Text       │ │
│                              │  Injector   │ │
│                              └─────────────┘ │
└─────────────────────────────────────────────┘
```

### Components

- **MenuBar Manager** — NSStatusItem with app icon. Menu contains "Settings..." and "Quit".
- **Settings Window** — SwiftUI window: model picker, language picker, hotkey recorder, launch-at-login toggle. Persisted via @AppStorage.
- **Hotkey Monitor** — Global NSEvent monitor for hold-to-record (keyDown starts, keyUp stops).
- **Audio Capture** — AVAudioEngine, captures microphone input into a buffer while hotkey is held.
- **MLX Whisper Engine** — Loads selected Whisper model via mlx-swift, runs transcription on background thread.
- **Text Injector** — CGEvent keystroke simulation to type transcribed text at cursor position.
- **Recording Indicator** — Small floating NSWindow near cursor showing recording state.

## Data Flow

### App Startup
1. Launch as LSUIElement (no dock icon)
2. Create NSStatusItem in menu bar
3. Check for downloaded model — if none, auto-download whisper-small
4. Preload selected model into memory
5. Register global hotkey monitor
6. Request Accessibility + Microphone permissions if needed

### Recording Flow
1. Hotkey down → start AVAudioEngine capture
2. Show floating indicator near cursor
3. User speaks while holding key
4. Hotkey up → stop capture, hide indicator
5. Pass audio buffer to MLX Whisper (background thread)
6. Show brief "processing" state on indicator
7. Receive transcription → inject via CGEvent keystrokes

## Model Management

- Models stored in `~/Library/Application Support/MyWhispers/models/<model-name>/`
- MLX-format weights downloaded from Hugging Face
- Available sizes: tiny, base, small, medium, large-v3
- Auto-download whisper-small on first launch
- Model switch in settings: unload → download if needed → preload

## Permissions

- **Microphone** — AVCaptureDevice.requestAccess. Required.
- **Accessibility** — CGEvent text injection. Must be granted in System Settings > Privacy > Accessibility. App guides user if not granted.

## Error Handling

- **Permission denied** — Alert via menu with button to open System Settings.
- **Model download fails** — Retry with exponential backoff, show error in menu bar.
- **Transcription fails** — Silent, no text injected. Brief flash on indicator.
- **No microphone input** — Detect silence, skip transcription.
- **Model not loaded** — Show "Loading model..." indicator, ignore hotkey press.

## Settings UI

```
┌─────────────────────────────────┐
│  MyWhispers Settings            │
│                                 │
│  Model:    [small ▾]            │
│  Language: [French ▾]           │
│  Hotkey:   [Right Option ⌥]    │
│  ☑ Launch at login              │
└─────────────────────────────────┘
```

## Tech Stack & Dependencies

- **mlx-swift** — ML inference on Apple Silicon
- **mlx-swift-examples/whisper** — Whisper model implementation (reference/adapt)
- **KeyboardShortcuts** (sindresorhus) — Global shortcut recording in settings
- **Build:** Swift Package Manager via Xcode

## Project Structure

```
MyWhispers/
├── MyWhispers.xcodeproj
├── Package.swift
├── Sources/
│   ├── App/
│   │   ├── MyWhispersApp.swift
│   │   └── AppState.swift
│   ├── MenuBar/
│   │   └── MenuBarManager.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   └── SettingsStore.swift
│   ├── Hotkey/
│   │   └── HotkeyMonitor.swift
│   ├── Audio/
│   │   └── AudioCapture.swift
│   ├── Whisper/
│   │   ├── WhisperEngine.swift
│   │   └── ModelManager.swift
│   ├── TextInjection/
│   │   └── TextInjector.swift
│   └── UI/
│       └── RecordingIndicator.swift
└── Resources/
    └── Assets.xcassets
```

## Key Design Decisions

- `AppState` is a single `@Observable` object shared across components
- `WhisperEngine` runs inference on a detached Task (off main thread)
- `ModelManager` handles Hugging Face downloads with progress reporting
- App is not sandboxed (required for Accessibility + global hotkey)
- Text injection via CGEvent keystroke simulation (works everywhere, requires Accessibility permission)
- Hold-to-record interaction (hold hotkey to record, release to transcribe)
