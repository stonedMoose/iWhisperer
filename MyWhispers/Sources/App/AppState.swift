import AVFoundation
import OSLog
import SwiftUI
import KeyboardShortcuts

@Observable
@MainActor
final class AppState {
    var isRecording = false
    var isProcessing = false
    var isModelLoaded = false
    var micPermissionGranted = false
    var accessibilityPermissionGranted = false
    var showPermissionAlert = false
    var permissionAlertMessage = ""

    private let whisperEngine = WhisperEngine()
    private let audioCapture = AudioCapture()
    private let recordingIndicator = RecordingIndicator()
    private let settingsStore: SettingsStore
    nonisolated(unsafe) private var modelChangeObserver: NSObjectProtocol?
    nonisolated(unsafe) private var permissionPollTask: Task<Void, Never>?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        setupHotkey()
        setupModelChangeListener()
        Task {
            await checkPermissionsAndSetup()
        }
    }

    private func checkPermissionsAndSetup() async {
        // Check microphone permission
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch micStatus {
        case .notDetermined:
            micPermissionGranted = await AudioCapture.requestPermission()
            Log.permissions.info("Microphone permission: \(self.micPermissionGranted ? "granted" : "denied")")
            if !micPermissionGranted {
                showPermissionError("Microphone access is required for speech-to-text. Please grant access in System Settings > Privacy & Security > Microphone.")
            }
        case .authorized:
            micPermissionGranted = true
        case .denied, .restricted:
            micPermissionGranted = false
            showPermissionError("Microphone access is required for speech-to-text. Please grant access in System Settings > Privacy & Security > Microphone.")
        @unknown default:
            micPermissionGranted = false
        }

        // Check accessibility permission
        accessibilityPermissionGranted = TextInjector.hasAccessibilityPermission
        Log.permissions.info("Accessibility permission: \(self.accessibilityPermissionGranted ? "granted" : "not granted")")
        if !accessibilityPermissionGranted {
            TextInjector.requestAccessibilityPermission()
        }

        // Poll for permissions until both are granted
        startPermissionPolling()

        // Load model regardless (so it's ready when permissions are granted)
        await loadModel()
    }

    private func startPermissionPolling() {
        guard !micPermissionGranted || !accessibilityPermissionGranted else { return }

        permissionPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }

                self.recheckPermissions()
                if self.micPermissionGranted && self.accessibilityPermissionGranted {
                    return
                }
            }
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func recheckPermissions() {
        micPermissionGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityPermissionGranted = TextInjector.hasAccessibilityPermission
    }

    private func showPermissionError(_ message: String) {
        permissionAlertMessage = message
        showPermissionAlert = true
    }

    private func setupModelChangeListener() {
        modelChangeObserver = NotificationCenter.default.addObserver(
            forName: .modelChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.loadModel()
            }
        }
    }

    deinit {
        permissionPollTask?.cancel()
        if let observer = modelChangeObserver {
            NotificationCenter.default.removeObserver(observer)
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
            Log.whisper.info("Loading model: \(self.settingsStore.selectedModel.rawValue)")
            try await whisperEngine.loadModel(settingsStore.selectedModel)
            isModelLoaded = true
            Log.whisper.info("Model loaded successfully")
        } catch {
            Log.whisper.error("Failed to load model: \(error)")
        }
    }

    private func startRecording() {
        guard isModelLoaded, !isProcessing else { return }

        // Recheck permissions each time
        recheckPermissions()

        guard micPermissionGranted else {
            showPermissionError("Microphone access is required. Please grant access in System Settings > Privacy & Security > Microphone.")
            return
        }

        guard accessibilityPermissionGranted else {
            TextInjector.requestAccessibilityPermission()
            return
        }

        do {
            try audioCapture.startRecording()
            isRecording = true
            recordingIndicator.show()
            Log.audio.info("Recording started")
        } catch {
            Log.audio.error("Failed to start recording: \(error)")
        }
    }

    private func stopRecordingAndTranscribe() async {
        guard isRecording else { return }

        let samples = audioCapture.stopRecording()
        isRecording = false
        Log.audio.info("Recording stopped, \(samples.count) samples captured")

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
            Log.whisper.info("Transcription result: \(text)")
            if !text.isEmpty {
                TextInjector.typeText(text)
            }
        } catch {
            Log.whisper.error("Transcription failed: \(error)")
        }

        isProcessing = false
        recordingIndicator.hide()
    }
}
