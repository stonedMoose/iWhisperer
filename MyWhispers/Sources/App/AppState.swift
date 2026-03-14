import AppKit
import AVFoundation
import OSLog
import SwiftUI
import KeyboardShortcuts
import UniformTypeIdentifiers
import UserNotifications


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
    var isMeetingRecording = false
    var isMeetingProcessing = false
    var meetingStatusMessage = ""
    var meetingElapsedTime: TimeInterval = 0

    private let whisperEngine = WhisperCppEngine()
    private let modelManager = ModelManager.shared
    private let audioCapture = AudioCapture()
    private let recordingIndicator = RecordingIndicator()
    private let settingsStore: SettingsStore
    private var modelChangeObserver: NSObjectProtocol?
    private var permissionPollTask: Task<Void, Never>?
    private var streamingLoopTask: Task<Void, Never>?
    private var streamingTypedWordCount = 0
    private var streamingPreviousWords: [String] = []
    private var streamingPromptTokens: [Int32] = []
    private var meetingRecorder: MeetingRecorder?
    private var meetingTimerTask: Task<Void, Never>?

    private static let streamStepMs = 3000
    private static let streamLengthMs = 10000
    private static let streamKeepMs = 200

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.meetingRecorder = MeetingRecorder(audioCapture: audioCapture, settingsStore: settingsStore)
        setupHotkey()
        setupModelChangeListener()
        setupNotificationDelegate()
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
        MainActor.assumeIsolated {
            permissionPollTask?.cancel()
            if let observer = modelChangeObserver {
                NotificationCenter.default.removeObserver(observer)
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
        KeyboardShortcuts.onKeyDown(for: .meetingRecord) { [weak self] in
            Task { @MainActor in
                await self?.toggleMeetingRecording()
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
            let path = try await modelManager.ensureModel(model) { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            }
            try await whisperEngine.loadModel(path: path)
            isDownloadingModel = false
            isModelLoaded = true
            Log.whisper.info("Model loaded successfully")
        } catch {
            isDownloadingModel = false
            Log.whisper.error("Failed to load model: \(error)")
        }
    }

    // MARK: - Recording

    private func startRecording() {
        guard isModelLoaded, !isProcessing, !isMeetingRecording, !isMeetingProcessing else { return }

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

        let language = settingsStore.selectedLanguage
        let text = await whisperEngine.transcribe(
            samples: samples,
            language: language == .auto ? "auto" : language.rawValue
        )
        Log.whisper.info("Transcription result: \(text, privacy: .private)")
        if !text.isEmpty {
            TextInjector.typeText(text)
        }

        isProcessing = false
        recordingIndicator.hide()
    }

    // MARK: - Streaming mode (sliding window + LocalAgreement)

    private func startStreamingRecording() {
        streamingTypedWordCount = 0
        streamingPreviousWords = []
        streamingPromptTokens = []

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

            let window = audioCapture.getWindow(
                lengthMs: Self.streamLengthMs,
                keepMs: Self.streamKeepMs
            )
            guard window.count >= minSamples else { continue }

            let language = settingsStore.selectedLanguage
            let langStr = language == .auto ? "auto" : language.rawValue

            let (text, tokens) = await whisperEngine.transcribeWindow(
                samples: window,
                language: langStr,
                promptTokens: streamingPromptTokens
            )

            guard !Task.isCancelled else { break }

            let currentWords = Self.splitIntoWords(text)
            guard !currentWords.isEmpty else {
                streamingPreviousWords = []
                continue
            }

            // Word-level LocalAgreement: longest common word prefix
            let stableCount = Self.longestCommonWordPrefix(currentWords, streamingPreviousWords)
            streamingPreviousWords = currentWords

            // Type only newly confirmed words
            if stableCount > streamingTypedWordCount {
                let newWords = Array(currentWords[streamingTypedWordCount..<stableCount])
                let prefix = streamingTypedWordCount == 0 ? "" : " "
                let newText = prefix + newWords.joined(separator: " ")
                if !newText.isEmpty {
                    Log.whisper.info("Streaming text: \(newText, privacy: .private)")
                    TextInjector.typeText(newText)
                    streamingTypedWordCount = stableCount
                }
            }

            // Feed tokens as prompt context for next iteration
            streamingPromptTokens = tokens
        }
    }

    private func stopStreamingRecording() async {
        streamingLoopTask?.cancel()
        await streamingLoopTask?.value
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

        // Final full inference on all captured audio
        let language = settingsStore.selectedLanguage
        let langStr = language == .auto ? "auto" : language.rawValue
        let finalText = await whisperEngine.transcribe(samples: samples, language: langStr)
        let finalWords = Self.splitIntoWords(finalText)

        if finalWords.count > streamingTypedWordCount {
            let remaining = Array(finalWords[streamingTypedWordCount...])
            let prefix = streamingTypedWordCount == 0 ? "" : " "
            let remainingText = prefix + remaining.joined(separator: " ")
            if !remainingText.isEmpty {
                Log.whisper.info("Streaming final: \(remainingText, privacy: .private)")
                TextInjector.typeText(remainingText)
            }
        } else if streamingTypedWordCount == 0 && !finalText.isEmpty {
            Log.whisper.info("Streaming fallback: \(finalText, privacy: .private)")
            TextInjector.typeText(finalText)
        }

        streamingTypedWordCount = 0
        streamingPreviousWords = []
        streamingPromptTokens = []
        isProcessing = false
        recordingIndicator.hide()
    }

    // MARK: - LocalAgreement helpers

    /// Split text into words, filtering empty strings.
    private static func splitIntoWords(_ text: String) -> [String] {
        text.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    /// Longest common word prefix between two word arrays.
    private static func longestCommonWordPrefix(_ a: [String], _ b: [String]) -> Int {
        var count = 0
        for (wa, wb) in zip(a, b) {
            if wa == wb { count += 1 } else { break }
        }
        return count
    }

    // MARK: - Meeting Recording

    func toggleMeetingRecording() async {
        if isMeetingRecording {
            await stopMeetingAndTranscribe()
        } else {
            startMeetingRecording()
        }
    }

    private func startMeetingRecording() {
        guard !isRecording, !isProcessing, !isMeetingProcessing else { return }

        recheckPermissions()
        guard micPermissionGranted else {
            showPermissionError("Microphone access is required. Please grant access in System Settings > Privacy & Security > Microphone.")
            return
        }

        do {
            try meetingRecorder?.startRecording()
            isMeetingRecording = true
            meetingElapsedTime = 0
            startMeetingTimer()
            Log.meeting.info("Meeting recording started")
        } catch {
            Log.meeting.error("Failed to start meeting recording: \(error)")
        }
    }

    private func stopMeetingAndTranscribe() async {
        guard isMeetingRecording, let recorder = meetingRecorder else { return }

        meetingTimerTask?.cancel()
        meetingTimerTask = nil

        guard let wavURL = recorder.stopRecording() else {
            isMeetingRecording = false
            return
        }

        isMeetingRecording = false
        isMeetingProcessing = true

        do {
            meetingStatusMessage = "Preparing models..."
            _ = try await ModelManager.shared.ensureDiarizationModel(.segmentation)
            _ = try await ModelManager.shared.ensureDiarizationModel(.embedding)
            meetingStatusMessage = "Transcribing & identifying speakers..."
            var markdown = try await recorder.transcribe(wavURL: wavURL)

            if settingsStore.refinementEnabled {
                meetingStatusMessage = "Refining transcript..."
                do {
                    markdown = try await TranscriptRefiner.shared.refine(
                        transcript: markdown,
                        prompt: settingsStore.refinementPrompt,
                        provider: settingsStore.refinementProvider,
                        apiKey: settingsStore.refinementAPIKey,
                        model: settingsStore.refinementModel
                    )
                } catch {
                    Log.meeting.error("Transcript refinement failed, saving raw transcript: \(error)")
                }
            }

            isMeetingProcessing = false
            meetingStatusMessage = ""
            saveTranscript(markdown: markdown)
        } catch {
            isMeetingProcessing = false
            meetingStatusMessage = ""
            Log.meeting.error("Meeting transcription failed: \(error)")
            showPermissionError(error.localizedDescription)
        }
    }

    func cancelMeetingTranscription() {
        isMeetingProcessing = false
        meetingStatusMessage = ""
    }

    private func startMeetingTimer() {
        meetingTimerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                meetingElapsedTime = meetingRecorder?.elapsedTime ?? 0
            }
        }
    }

    private func saveTranscript(markdown: String) {
        let dir = settingsStore.transcriptDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let filename = "Meeting-\(formatter.string(from: Date())).md"
        let url = dir.appendingPathComponent(filename)

        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            Log.meeting.info("Meeting transcript saved to: \(url.path)")
            sendTranscriptNotification(fileURL: url)
        } catch {
            Log.meeting.error("Failed to save transcript: \(error)")
            showPermissionError("Failed to save transcript: \(error.localizedDescription)")
        }
    }

    private func sendTranscriptNotification(fileURL: URL) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "Meeting Transcript Ready"
            content.body = "Saved to \(fileURL.lastPathComponent)"
            content.sound = .default
            content.userInfo = ["fileURL": fileURL.absoluteString]

            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }

    private func setupNotificationDelegate() {
        UNUserNotificationCenter.current().delegate = NotificationHandler.shared
    }
}

final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationHandler()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let urlString = response.notification.request.content.userInfo["fileURL"] as? String,
           let url = URL(string: urlString) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
