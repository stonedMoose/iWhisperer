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

    private static let streamStepMs = 3000 // How often to transcribe during streaming (ms)

    private var streamingLoopTask: Task<Void, Never>?
    private var streamingTypedCount = 0
    private var lastStreamingResult = ""

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

    // MARK: - Batch mode

    private func startBatchRecording() {
        do {
            try audioCapture.startRecording()
            guard recordingIndicator.show() else {
                _ = audioCapture.stopRecording()
                return
            }
            isRecording = true
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

    // MARK: - Streaming mode (sliding window)

    private static func cleanTranscriptionText(_ text: String) -> String {
        text.replacingOccurrences(
            of: "<\\|[^|]*\\|>",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
    }

    /// Number of leading characters that are identical in both strings.
    private static func commonPrefixCount(_ a: String, _ b: String) -> Int {
        var count = 0
        for (ca, cb) in zip(a, b) {
            if ca == cb { count += 1 } else { break }
        }
        return count
    }

    private func startStreamingRecording() {
        streamingTypedCount = 0
        lastStreamingResult = ""

        do {
            try audioCapture.startRecording()
            guard recordingIndicator.show() else {
                _ = audioCapture.stopRecording()
                return
            }
            isRecording = true
            Log.audio.info("Recording started (streaming mode)")

            streamingLoopTask = Task {
                await streamingLoop()
            }
        } catch {
            Log.audio.error("Failed to start streaming recording: \(error)")
        }
    }

    private func streamingLoop() async {
        let minSamples = Self.streamStepMs * 16 // 16kHz = 16 samples per ms

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(Self.streamStepMs))
            guard !Task.isCancelled else { break }

            let samples = audioCapture.peekSamples()
            guard samples.count >= minSamples else { continue }

            do {
                let fullText = try await whisperEngine.transcribe(
                    audioSamples: samples,
                    language: settingsStore.selectedLanguage
                )
                guard !Task.isCancelled else { break }

                let cleanText = Self.cleanTranscriptionText(fullText)
                guard !cleanText.isEmpty else {
                    lastStreamingResult = ""
                    continue
                }

                // Text that is identical across two consecutive transcriptions is "stable"
                let stableCount = Self.commonPrefixCount(cleanText, lastStreamingResult)
                lastStreamingResult = cleanText

                // Type newly stable characters that haven't been typed yet
                if stableCount > streamingTypedCount {
                    let startIdx = cleanText.index(cleanText.startIndex, offsetBy: streamingTypedCount)
                    let endIdx = cleanText.index(cleanText.startIndex, offsetBy: stableCount)
                    let newText = String(cleanText[startIdx..<endIdx])
                    if !newText.isEmpty {
                        Log.whisper.info("Streaming text: \(newText)")
                        TextInjector.typeText(newText)
                        streamingTypedCount = stableCount
                    }
                }
            } catch {
                Log.whisper.error("Streaming transcription step failed: \(error)")
            }
        }
    }

    private func stopStreamingRecording() async {
        streamingLoopTask?.cancel()
        streamingLoopTask = nil

        let samples = audioCapture.stopRecording()
        isRecording = false
        Log.audio.info("Streaming stopped, \(samples.count) samples captured")

        guard !samples.isEmpty else {
            recordingIndicator.hide()
            return
        }

        isProcessing = true
        recordingIndicator.showProcessing()

        do {
            let fullText = try await whisperEngine.transcribe(
                audioSamples: samples,
                language: settingsStore.selectedLanguage
            )
            let cleanText = Self.cleanTranscriptionText(fullText)

            if cleanText.count > streamingTypedCount {
                let remaining = String(cleanText.dropFirst(streamingTypedCount))
                if !remaining.isEmpty {
                    Log.whisper.info("Streaming final: \(remaining)")
                    TextInjector.typeText(remaining)
                }
            } else if streamingTypedCount == 0 && !cleanText.isEmpty {
                Log.whisper.info("Streaming fallback: \(cleanText)")
                TextInjector.typeText(cleanText)
            }
        } catch {
            Log.whisper.error("Streaming final transcription failed: \(error)")
        }

        streamingTypedCount = 0
        lastStreamingResult = ""
        isProcessing = false
        recordingIndicator.hide()
        Log.audio.info("Streaming recording stopped")
    }
}
