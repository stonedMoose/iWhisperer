import AVFoundation
import OSLog
import SwiftUI
import KeyboardShortcuts
import WhisperKit

@Observable
@MainActor
final class AppState {
    var isRecording = false
    var isProcessing = false
    var isModelLoaded = false
    var isDownloadingModel = false
    var downloadProgress: Double = 0
    var downloadingModelName: String = ""
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

    func relaunch() {
        // Relaunch the .app bundle (not the raw executable) so macOS TCC
        // correctly matches the new process to the granted permissions.
        if let bundleURL = Bundle.main.bundleURL as URL?,
           bundleURL.pathExtension == "app" {
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
                DispatchQueue.main.async {
                    NSApplication.shared.terminate(nil)
                }
            }
        } else {
            // Fallback: raw executable (e.g. running from swift build)
            let executablePath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = []
            try? process.run()
            NSApplication.shared.terminate(nil)
        }
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
        isDownloadingModel = false
        downloadProgress = 0
        let model = settingsStore.selectedModel
        downloadingModelName = model.displayName
        do {
            Log.whisper.info("Loading model: \(model.rawValue)")
            isDownloadingModel = true
            try await whisperEngine.loadModel(model) { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            }
            isDownloadingModel = false
            isModelLoaded = true
            Log.whisper.info("Model loaded successfully")
        } catch {
            isDownloadingModel = false
            Log.whisper.error("Failed to load model: \(error)")
        }
    }

    // MARK: - Recording

    private var lastInjectedSegmentCount = 0
    private var lastStreamingState: AudioStreamTranscriber.State?
    private var streamingTask: Task<Void, Never>?
    private var streamingInjectedText = ""

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

        if settingsStore.streamingMode {
            startStreamingRecording()
        } else {
            startBatchRecording()
        }
    }

    private func stopRecordingAndTranscribe() async {
        guard isRecording else { return }

        if settingsStore.streamingMode {
            await stopStreamingRecording()
        } else {
            await stopBatchRecording()
        }
    }

    // MARK: - Batch mode (original)

    private func startBatchRecording() {
        do {
            try audioCapture.startRecording()
            isRecording = true
            recordingIndicator.show()
            Log.audio.info("Recording started (batch mode)")
        } catch {
            Log.audio.error("Failed to start recording: \(error)")
        }
    }

    private func stopBatchRecording() async {
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

    // MARK: - Streaming mode

    private func startStreamingRecording() {
        lastInjectedSegmentCount = 0
        lastStreamingState = nil
        streamingInjectedText = ""
        isRecording = true
        recordingIndicator.show()
        Log.audio.info("Recording started (streaming mode)")

        streamingTask = Task {
            do {
                try await whisperEngine.startStreaming(
                    language: settingsStore.selectedLanguage
                ) { [weak self] oldState, newState in
                    Task { @MainActor [weak self] in
                        self?.handleStreamingStateChange(oldState: oldState, newState: newState)
                    }
                }
            } catch {
                Log.whisper.error("Streaming transcription failed: \(error)")
                self.isRecording = false
                self.recordingIndicator.hide()
            }
        }
    }

    private static func cleanTranscriptionText(_ text: String) -> String {
        // Strip any special tokens that leaked through (e.g. <|startoftranscript|>, <|en|>, <|0.00|>)
        text.replacingOccurrences(
            of: "<\\|[^|]*\\|>",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
    }

    private func handleStreamingStateChange(oldState: AudioStreamTranscriber.State, newState: AudioStreamTranscriber.State) {
        lastStreamingState = newState

        // Inject newly confirmed segments
        let newConfirmedCount = newState.confirmedSegments.count
        if newConfirmedCount > lastInjectedSegmentCount {
            let newSegments = newState.confirmedSegments[lastInjectedSegmentCount...]
            let raw = newSegments.map(\.text).joined(separator: " ")
            let text = Self.cleanTranscriptionText(raw)
            if !text.isEmpty {
                Log.whisper.info("Streaming confirmed text: \(text)")
                TextInjector.typeText(text)
                streamingInjectedText += text
            }
            lastInjectedSegmentCount = newConfirmedCount
        }
    }

    private func stopStreamingRecording() async {
        let remainingSamples = await whisperEngine.stopStreaming()
        streamingTask?.cancel()
        streamingTask = nil

        // Try to flush unconfirmed segments from the last streaming state
        var flushedText = ""
        if let state = lastStreamingState {
            let raw = state.unconfirmedSegments
                .map(\.text)
                .joined(separator: " ")
            let unconfirmedText = Self.cleanTranscriptionText(raw)
            if !unconfirmedText.isEmpty {
                Log.whisper.info("Streaming flush unconfirmed: \(unconfirmedText)")
                TextInjector.typeText(unconfirmedText)
                flushedText = unconfirmedText
            }
        }

        // FALLBACK: If streaming produced NO output at all, batch-transcribe
        let totalStreamingOutput = streamingInjectedText + flushedText
        if totalStreamingOutput.isEmpty && !remainingSamples.isEmpty {
            Log.whisper.info("Streaming produced no output, falling back to batch transcription (\(remainingSamples.count) samples)")
            isProcessing = true
            recordingIndicator.showProcessing()

            do {
                let text = try await whisperEngine.transcribe(
                    audioSamples: remainingSamples,
                    language: settingsStore.selectedLanguage
                )
                Log.whisper.info("Batch fallback result: \(text)")
                if !text.isEmpty {
                    TextInjector.typeText(text)
                }
            } catch {
                Log.whisper.error("Batch fallback transcription failed: \(error)")
            }

            isProcessing = false
        }

        lastStreamingState = nil
        streamingInjectedText = ""
        isRecording = false
        recordingIndicator.hide()
        Log.audio.info("Streaming recording stopped")
    }
}
