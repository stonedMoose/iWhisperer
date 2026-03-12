import AVFoundation
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
        setupModelChangeListener()
        Task {
            let granted = await AudioCapture.requestPermission()
            if !granted {
                print("Microphone permission denied")
            }
            await loadModel()
        }
    }

    private func setupModelChangeListener() {
        NotificationCenter.default.addObserver(
            forName: .modelChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.loadModel()
            }
        }
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

        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            Task { _ = await AudioCapture.requestPermission() }
            return
        }

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
