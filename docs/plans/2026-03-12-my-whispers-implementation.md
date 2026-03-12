# MyWhispers Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS menu bar app that transcribes speech to text at the cursor position using Whisper, triggered by a configurable hold-to-record hotkey.

**Architecture:** SwiftUI menu bar app (LSUIElement) with WhisperKit for on-device Whisper inference, KeyboardShortcuts for hotkey management, AVAudioEngine for mic capture, and CGEvent for text injection. Single `@Observable` AppState coordinates all components.

**Tech Stack:** Swift 5.9+, SwiftUI, WhisperKit (CoreML-based Whisper), KeyboardShortcuts (sindresorhus), macOS 14+, Apple Silicon only.

**Design revision:** Using WhisperKit (`https://github.com/argmaxinc/WhisperKit`) instead of raw mlx-swift. WhisperKit provides a battle-tested, Swift-native Whisper implementation with CoreML optimization, automatic model downloading, and a simple `transcribe()` API. The mlx-swift-examples repo does not have a Whisper implementation.

---

## Task 1: Xcode Project & SPM Dependencies

**Files:**
- Create: `MyWhispers/Package.swift`
- Create: `MyWhispers/Sources/App/MyWhispersApp.swift`
- Create: `MyWhispers/Sources/App/AppState.swift`

**Step 1: Create the project directory structure**

```bash
mkdir -p MyWhispers/Sources/App
mkdir -p MyWhispers/Sources/MenuBar
mkdir -p MyWhispers/Sources/Settings
mkdir -p MyWhispers/Sources/Hotkey
mkdir -p MyWhispers/Sources/Audio
mkdir -p MyWhispers/Sources/Whisper
mkdir -p MyWhispers/Sources/TextInjection
mkdir -p MyWhispers/Sources/UI
mkdir -p MyWhispers/Resources/Assets.xcassets/AppIcon.appiconset
```

**Step 2: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyWhispers",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MyWhispers",
            dependencies: [
                "WhisperKit",
                "KeyboardShortcuts",
            ],
            path: "Sources",
            resources: [
                .process("../Resources"),
            ]
        ),
    ]
)
```

**Step 3: Create minimal app entry point**

Create `Sources/App/MyWhispersApp.swift`:

```swift
import SwiftUI

@main
struct MyWhispersApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("MyWhispers", systemImage: "mic.fill") {
            Text("MyWhispers")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
```

Create `Sources/App/AppState.swift`:

```swift
import SwiftUI

@Observable
@MainActor
final class AppState {
    var isRecording = false
    var isProcessing = false
    var isModelLoaded = false
    var modelLoadingProgress: Double = 0
}
```

**Step 4: Verify it builds**

```bash
cd MyWhispers && swift build
```

Expected: Builds successfully, downloads WhisperKit and KeyboardShortcuts dependencies.

**Step 5: Configure Info.plist for LSUIElement**

Create `Sources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>MyWhispers needs microphone access to record speech for transcription.</string>
</dict>
</plist>
```

**Step 6: Commit**

```bash
git add .
git commit -m "feat: scaffold project with SPM, WhisperKit, KeyboardShortcuts deps"
```

---

## Task 2: Settings Store & Model/Language Definitions

**Files:**
- Create: `Sources/Settings/SettingsStore.swift`
- Create: `Sources/Whisper/WhisperModels.swift`

**Step 1: Define available Whisper models**

Create `Sources/Whisper/WhisperModels.swift`:

```swift
import Foundation

enum WhisperModel: String, CaseIterable, Identifiable, Codable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"
    case largev3 = "large-v3"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: "Tiny (~75 MB)"
        case .base: "Base (~140 MB)"
        case .small: "Small (~460 MB)"
        case .medium: "Medium (~1.5 GB)"
        case .largev3: "Large v3 (~3 GB)"
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

**Step 2: Create SettingsStore**

Create `Sources/Settings/SettingsStore.swift`:

```swift
import SwiftUI

@Observable
@MainActor
final class SettingsStore {
    @AppStorage("selectedModel") var selectedModel: WhisperModel = .small
    @AppStorage("selectedLanguage") var selectedLanguage: WhisperLanguage = .auto
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
}
```

> **Note:** `@AppStorage` with custom `RawRepresentable` enums works because they conform to `Codable` with `String` raw values.

**Step 3: Verify it builds**

```bash
swift build
```

**Step 4: Commit**

```bash
git add .
git commit -m "feat: add settings store with model and language definitions"
```

---

## Task 3: Settings Window UI

**Files:**
- Create: `Sources/Settings/SettingsView.swift`
- Modify: `Sources/App/MyWhispersApp.swift`
- Modify: `Sources/App/AppState.swift`

**Step 1: Create SettingsView**

Create `Sources/Settings/SettingsView.swift`:

```swift
import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let holdToRecord = Self("holdToRecord")
}

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Speech Recognition") {
                Picker("Model", selection: $settings.selectedModel) {
                    ForEach(WhisperModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }

                Picker("Language", selection: $settings.selectedLanguage) {
                    ForEach(WhisperLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
            }

            Section("Shortcut") {
                KeyboardShortcuts.Recorder("Hold to record:", name: .holdToRecord)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 280)
    }
}
```

**Step 2: Wire settings window into the app**

Update `Sources/App/MyWhispersApp.swift`:

```swift
import SwiftUI

@main
struct MyWhispersApp: App {
    @State private var appState = AppState()
    @State private var settingsStore = SettingsStore()

    var body: some Scene {
        MenuBarExtra("MyWhispers", systemImage: appState.isRecording ? "mic.fill" : "mic") {
            if appState.isProcessing {
                Text("Transcribing...")
            } else if appState.isRecording {
                Text("Recording...")
            } else if !appState.isModelLoaded {
                Text("Loading model...")
            } else {
                Text("Ready")
            }

            Divider()

            Button("Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title == "MyWhispers Settings" }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit MyWhispers") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .menuBarExtraStyle(.menu)

        Window("MyWhispers Settings", id: "settings") {
            SettingsView()
                .environment(settingsStore)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
```

**Step 3: Verify it builds**

```bash
swift build
```

**Step 4: Commit**

```bash
git add .
git commit -m "feat: add settings window with model, language, and hotkey pickers"
```

---

## Task 4: Audio Capture

**Files:**
- Create: `Sources/Audio/AudioCapture.swift`

**Step 1: Implement AudioCapture**

Create `Sources/Audio/AudioCapture.swift`:

```swift
import AVFoundation
import Foundation

final class AudioCapture {
    private let engine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()

    /// Request microphone permission. Returns true if granted.
    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Start capturing audio from the microphone.
    func startRecording() throws {
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let frameCount = Int(buffer.frameLength)
            guard let channelData = buffer.floatChannelData?[0] else { return }

            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

            self.bufferLock.lock()
            self.audioBuffer.append(contentsOf: samples)
            self.bufferLock.unlock()
        }

        engine.prepare()
        try engine.start()
    }

    /// Stop recording and return the captured audio samples at 16kHz mono.
    func stopRecording() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        bufferLock.lock()
        let samples = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()

        return samples
    }
}
```

**Step 2: Verify it builds**

```bash
swift build
```

**Step 3: Commit**

```bash
git add .
git commit -m "feat: add AVAudioEngine-based audio capture"
```

---

## Task 5: WhisperKit Engine Integration

**Files:**
- Create: `Sources/Whisper/WhisperEngine.swift`

**Step 1: Implement WhisperEngine**

Create `Sources/Whisper/WhisperEngine.swift`:

```swift
import Foundation
import WhisperKit

actor WhisperEngine {
    private var whisperKit: WhisperKit?
    private var currentModel: WhisperModel?

    var isLoaded: Bool { whisperKit != nil }

    /// Load (or reload) a Whisper model. Downloads from HuggingFace if not cached.
    func loadModel(_ model: WhisperModel) async throws {
        if currentModel == model && whisperKit != nil { return }

        whisperKit = nil
        currentModel = nil

        let config = WhisperKitConfig(model: model.rawValue)
        whisperKit = try await WhisperKit(config)
        currentModel = model
    }

    /// Transcribe audio samples (16kHz Float array) to text.
    func transcribe(audioSamples: [Float], language: WhisperLanguage) async throws -> String {
        guard let whisperKit else {
            throw WhisperEngineError.modelNotLoaded
        }

        let options = DecodingOptions(
            language: language == .auto ? nil : language.rawValue
        )

        let results = try await whisperKit.transcribe(
            audioArray: audioSamples,
            decodeOptions: options
        )

        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}

enum WhisperEngineError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: "No Whisper model is loaded."
        }
    }
}
```

> **Note:** The exact WhisperKit API may need adjustment based on the installed version. The key pattern is: init with model name, call `transcribe(audioArray:decodeOptions:)`. Check WhisperKit docs if the API has changed.

**Step 2: Verify it builds**

```bash
swift build
```

**Step 3: Commit**

```bash
git add .
git commit -m "feat: add WhisperKit engine wrapper with model loading and transcription"
```

---

## Task 6: Text Injector (CGEvent)

**Files:**
- Create: `Sources/TextInjection/TextInjector.swift`

**Step 1: Implement TextInjector**

Create `Sources/TextInjection/TextInjector.swift`:

```swift
import CoreGraphics
import Foundation

@MainActor
struct TextInjector {

    /// Check if the app has Accessibility permission.
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt: false] as CFDictionary
        )
    }

    /// Prompt the user to grant Accessibility permission.
    static func requestAccessibilityPermission() {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt: true] as CFDictionary
        )
    }

    /// Type text at the current cursor position using CGEvent keyboard simulation.
    static func typeText(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)

        for character in text {
            let utf16 = Array(String(character).utf16)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)

            keyDown?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUp?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)

            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}
```

**Step 2: Verify it builds**

```bash
swift build
```

**Step 3: Commit**

```bash
git add .
git commit -m "feat: add CGEvent-based text injector with accessibility check"
```

---

## Task 7: Recording Indicator (Floating Dot)

**Files:**
- Create: `Sources/UI/RecordingIndicator.swift`

**Step 1: Implement RecordingIndicator**

Create `Sources/UI/RecordingIndicator.swift`:

```swift
import AppKit
import SwiftUI

@MainActor
final class RecordingIndicator {
    private var window: NSWindow?

    func show() {
        guard window == nil else { return }

        let size: CGFloat = 20
        let mouseLocation = NSEvent.mouseLocation

        let panel = NSPanel(
            contentRect: NSRect(
                x: mouseLocation.x + 16,
                y: mouseLocation.y - size - 8,
                width: size,
                height: size
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(rootView: RecordingDot())
        panel.contentView = hostingView
        panel.orderFrontRegardless()

        window = panel
    }

    func showProcessing() {
        guard let panel = window else { return }
        let hostingView = NSHostingView(rootView: ProcessingDot())
        panel.contentView = hostingView
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

private struct RecordingDot: View {
    @State private var opacity: Double = 1.0

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 16, height: 16)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    opacity = 0.4
                }
            }
    }
}

private struct ProcessingDot: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(.orange, lineWidth: 2)
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
```

**Step 2: Verify it builds**

```bash
swift build
```

**Step 3: Commit**

```bash
git add .
git commit -m "feat: add floating recording indicator with pulsing red dot"
```

---

## Task 8: Hotkey Monitor & Recording Orchestration

**Files:**
- Modify: `Sources/App/AppState.swift`

**Step 1: Wire everything together in AppState**

Rewrite `Sources/App/AppState.swift`:

```swift
import SwiftUI
import KeyboardShortcuts

@Observable
@MainActor
final class AppState {
    var isRecording = false
    var isProcessing = false
    var isModelLoaded = false

    private let whisperEngine = WhisperEngine()
    private let audioCapture = AudioCapture()
    private let recordingIndicator = RecordingIndicator()
    private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        setupHotkey()
        Task { await loadModel() }
    }

    private func setupHotkey() {
        KeyboardShortcuts.onKeyDown(for: .holdToRecord) { [weak self] in
            Task { @MainActor in
                self?.startRecording()
            }
        }
        KeyboardShortcuts.onKeyUp(for: .holdToRecord) { [weak self] in
            Task { @MainActor in
                await self?.stopRecordingAndTranscribe()
            }
        }
    }

    func loadModel() async {
        isModelLoaded = false
        do {
            try await whisperEngine.loadModel(settingsStore.selectedModel)
            isModelLoaded = true
        } catch {
            print("Failed to load model: \(error)")
        }
    }

    private func startRecording() {
        guard isModelLoaded, !isProcessing else { return }

        guard TextInjector.hasAccessibilityPermission else {
            TextInjector.requestAccessibilityPermission()
            return
        }

        do {
            try audioCapture.startRecording()
            isRecording = true
            recordingIndicator.show()
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    private func stopRecordingAndTranscribe() async {
        guard isRecording else { return }

        let samples = audioCapture.stopRecording()
        isRecording = false

        guard !samples.isEmpty else {
            recordingIndicator.hide()
            return
        }

        isProcessing = true
        recordingIndicator.showProcessing()

        do {
            let text = try await whisperEngine.transcribe(
                audioSamples: samples,
                language: settingsStore.selectedLanguage
            )
            if !text.isEmpty {
                TextInjector.typeText(text)
            }
        } catch {
            print("Transcription failed: \(error)")
        }

        isProcessing = false
        recordingIndicator.hide()
    }
}
```

**Step 2: Update MyWhispersApp to pass settingsStore to AppState**

Update `Sources/App/MyWhispersApp.swift` — change the `appState` initialization:

```swift
import SwiftUI

@main
struct MyWhispersApp: App {
    @State private var settingsStore = SettingsStore()
    @State private var appState: AppState?

    var body: some Scene {
        MenuBarExtra("MyWhispers", systemImage: appState?.isRecording == true ? "mic.fill" : "mic") {
            if let appState {
                if appState.isProcessing {
                    Text("Transcribing...")
                } else if appState.isRecording {
                    Text("Recording...")
                } else if !appState.isModelLoaded {
                    Text("Loading model...")
                } else {
                    Text("Ready")
                }
            } else {
                Text("Starting...")
            }

            Divider()

            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit MyWhispers") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .menuBarExtraStyle(.menu)

        Window("MyWhispers Settings", id: "settings") {
            SettingsView()
                .environment(settingsStore)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environment(settingsStore)
        }
    }

    init() {
        let store = SettingsStore()
        _settingsStore = State(initialValue: store)
        _appState = State(initialValue: AppState(settingsStore: store))
    }
}
```

**Step 3: Verify it builds**

```bash
swift build
```

**Step 4: Commit**

```bash
git add .
git commit -m "feat: wire hotkey, recording, transcription, and text injection together"
```

---

## Task 9: Model Reload on Settings Change

**Files:**
- Modify: `Sources/Settings/SettingsView.swift`
- Modify: `Sources/App/AppState.swift`

**Step 1: Add model reload trigger**

In `Sources/Settings/SettingsView.swift`, add an `onChange` to the model picker:

```swift
Picker("Model", selection: $settings.selectedModel) {
    ForEach(WhisperModel.allCases) { model in
        Text(model.displayName).tag(model)
    }
}
.onChange(of: settings.selectedModel) { _, _ in
    NotificationCenter.default.post(name: .modelChanged, object: nil)
}
```

Add notification name extension at the file level:

```swift
extension Notification.Name {
    static let modelChanged = Notification.Name("modelChanged")
}
```

**Step 2: Listen for model changes in AppState**

Add to `AppState.init`, after `setupHotkey()`:

```swift
NotificationCenter.default.addObserver(
    forName: .modelChanged,
    object: nil,
    queue: .main
) { [weak self] _ in
    Task { @MainActor in
        await self?.loadModel()
    }
}
```

**Step 3: Verify it builds**

```bash
swift build
```

**Step 4: Commit**

```bash
git add .
git commit -m "feat: reload Whisper model when user changes model in settings"
```

---

## Task 10: Launch at Login

**Files:**
- Modify: `Sources/Settings/SettingsView.swift`

**Step 1: Implement launch at login using ServiceManagement**

Update the `launchAtLogin` toggle in `SettingsView.swift`:

```swift
import ServiceManagement

// In the "General" section:
Toggle("Launch at login", isOn: $settings.launchAtLogin)
    .onChange(of: settings.launchAtLogin) { _, newValue in
        do {
            if newValue {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update login item: \(error)")
        }
    }
```

**Step 2: Verify it builds**

```bash
swift build
```

**Step 3: Commit**

```bash
git add .
git commit -m "feat: add launch at login via ServiceManagement"
```

---

## Task 11: Microphone Permission Handling

**Files:**
- Modify: `Sources/App/AppState.swift`

**Step 1: Request microphone permission on startup**

Add to the `init` of `AppState`, before `Task { await loadModel() }`:

```swift
Task {
    let granted = await AudioCapture.requestPermission()
    if !granted {
        print("Microphone permission denied")
    }
    await loadModel()
}
```

**Step 2: Guard recording on permission**

In `startRecording()`, add at the top:

```swift
guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
    Task { _ = await AudioCapture.requestPermission() }
    return
}
```

Add `import AVFoundation` to the top of AppState.swift.

**Step 3: Verify it builds**

```bash
swift build
```

**Step 4: Commit**

```bash
git add .
git commit -m "feat: request microphone permission on startup"
```

---

## Task 12: End-to-End Manual Testing

**Files:** None (testing only)

**Step 1: Build and run the app**

```bash
cd MyWhispers && swift build && .build/debug/MyWhispers
```

**Step 2: Test checklist**

- [ ] App appears in menu bar with mic icon
- [ ] Clicking "Settings..." opens the settings window
- [ ] Model picker shows all model sizes
- [ ] Language picker shows all languages
- [ ] Hotkey recorder works (set a shortcut)
- [ ] On first launch, model downloads automatically (check console for progress)
- [ ] Holding the hotkey shows the red pulsing dot near cursor
- [ ] Speaking and releasing transcribes and types text at cursor
- [ ] Accessibility permission prompt appears on first hotkey press
- [ ] "Quit" menu item exits the app
- [ ] Changing model in settings triggers model reload

**Step 3: Fix any issues found during testing**

Address any build errors, API mismatches with WhisperKit, or UI issues.

**Step 4: Commit any fixes**

```bash
git add .
git commit -m "fix: address issues found during manual testing"
```

---

## Task 13: App Icon & Polish

**Files:**
- Create: `Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`

**Step 1: Create a basic app icon asset catalog entry**

Create `Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{
  "images" : [
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

**Step 2: Create Contents.json for the asset catalog root**

Create `Resources/Assets.xcassets/Contents.json`:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

**Step 3: Commit**

```bash
git add .
git commit -m "chore: add app icon asset catalog structure"
```
