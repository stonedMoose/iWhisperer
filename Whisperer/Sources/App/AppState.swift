import AppKit
import AVFoundation
import OSLog
import SwiftUI
import KeyboardShortcuts
import UniformTypeIdentifiers
@preconcurrency import UserNotifications


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
    var showSetupWindow = false

    private let whisperEngine = WhisperCppEngine()
    /// Separate engine for streaming so it can run a lighter model concurrently.
    private let streamingEngine = WhisperCppEngine()
    private let modelManager = ModelManager.shared
    private let audioCapture = AudioCapture()
    private let recordingIndicator = RecordingIndicator()
    private let settingsStore: SettingsStore
    private var modelChangeObserver: NSObjectProtocol?
    private var streamingModelChangeObserver: NSObjectProtocol?
    private var permissionPollTask: Task<Void, Never>?
    private var streamingLoopTask: Task<Void, Never>?
    var isStreamingModelLoaded = false
    private var streamingCommittedWords: [String] = []
    private var streamingPreviousWords: [String] = []
    private var streamingPromptTokens: [Int32] = []
    private var meetingRecorder: MeetingRecorder?
    private var meetingTimerTask: Task<Void, Never>?

    /// The model actually used for streaming: explicit streaming model if set, else the batch model.
    var effectiveStreamingModel: WhisperModel {
        settingsStore.streamingModel ?? settingsStore.selectedModel
    }

    // Streaming timing — model-adaptive so small models aren't penalised.
    // First-step is shorter to get words on screen fast; subsequent steps
    // are longer for stability (LocalAgreement needs two windows to agree).
    private var streamFirstStepMs: Int {
        switch effectiveStreamingModel {
        case .tiny:   return 300
        case .base:   return 400
        case .small:  return 600
        case .medium: return 900
        case .largev3: return 1200
        }
    }
    private var streamStepMs: Int {
        switch effectiveStreamingModel {
        case .tiny:   return 600
        case .base:   return 800
        case .small:  return 1200
        case .medium: return 1600
        case .largev3: return 2000
        }
    }
    private var streamLengthMs: Int { streamStepMs * 4 }
    private static let streamKeepMs = 200

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.meetingRecorder = MeetingRecorder(audioCapture: audioCapture, settingsStore: settingsStore)
        setupHotkey()
        setupModelChangeListener()
        setupStreamingModelChangeListener()
        setupNotificationDelegate()
        RecordingIndicator.installClickMonitor()
        Task {
            await checkPermissionsAndSetup()
            if !settingsStore.hasCompletedSetup {
                showSetupWindow = true
            }
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

        // Load batch model regardless (so it's ready when permissions are granted)
        await loadModel()
        // Load streaming model if it differs from the batch model
        if settingsStore.streamingModel != nil {
            await loadStreamingModel()
        }
    }

    private func startPermissionPolling() {
        permissionPollTask?.cancel()
        permissionPollTask = nil

        guard !micPermissionGranted || !accessibilityPermissionGranted else { return }

        permissionPollTask = Task { [weak self] in
            // Poll up to 30 times (~60 seconds) then stop to avoid infinite loop
            for _ in 0..<30 {
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

        // Restart polling if permissions are still missing
        if !micPermissionGranted || !accessibilityPermissionGranted {
            startPermissionPolling()
        } else {
            permissionPollTask?.cancel()
            permissionPollTask = nil
        }
    }

    /// Cleanly release whisper.cpp resources before app termination.
    /// This prevents a race condition where exit() triggers C++ static
    /// destructors (ggml_metal_device_free) while a background thread is
    /// still initializing Metal resource sets, causing ggml_abort.
    func prepareForTermination() async {
        await whisperEngine.unloadModel()
        await streamingEngine.unloadModel()
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
                // Re-load streaming model too if it follows the batch model
                if self?.settingsStore.streamingModel == nil {
                    await self?.loadStreamingModel()
                }
            }
        }
    }

    private func setupStreamingModelChangeListener() {
        streamingModelChangeObserver = NotificationCenter.default.addObserver(
            forName: .streamingModelChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.loadStreamingModel()
            }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            permissionPollTask?.cancel()
            if let observer = modelChangeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = streamingModelChangeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    func cycleLanguage() {
        let preferred = settingsStore.preferredLanguages
        let options: [WhisperLanguage] = preferred.count >= 2 ? preferred : [.auto] + preferred
        guard options.count > 1 else { return }
        let current = settingsStore.selectedLanguage
        let idx = options.firstIndex(of: current) ?? -1
        settingsStore.selectedLanguage = options[(idx + 1) % options.count]
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
        KeyboardShortcuts.onKeyDown(for: .cycleLanguage) { [weak self] in
            Task { @MainActor in
                self?.cycleLanguage()
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

    /// Load the streaming-specific model into `streamingEngine`.
    /// Falls back to the batch model when no streaming model is explicitly set.
    func loadStreamingModel() async {
        isStreamingModelLoaded = false
        let model = effectiveStreamingModel
        do {
            Log.whisper.info("Loading streaming model: \(model.rawValue)")
            let path = try await modelManager.ensureModel(model) { _ in }
            try await streamingEngine.loadModel(path: path)
            isStreamingModelLoaded = true
            Log.whisper.info("Streaming model loaded successfully")
        } catch {
            Log.whisper.error("Failed to load streaming model: \(error)")
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
            try audioCapture.startRecording(deviceUID: settingsStore.selectedMicrophoneUID)
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

        defer {
            isProcessing = false
            recordingIndicator.hide()
        }

        let language = settingsStore.selectedLanguage
        do {
            let text = try await whisperEngine.transcribe(
                samples: samples,
                language: language == .auto ? "auto" : language.rawValue
            )
            Log.whisper.info("Transcription result: \(text, privacy: .private)")
            if !text.isEmpty {
                await TextInjector.typeText(text)
            }
        } catch {
            Log.whisper.error("Transcription failed: \(error)")
            showPermissionError("Transcription failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Streaming mode (sliding window + LocalAgreement)

    private func startStreamingRecording() {
        // Ensure the streaming model is loaded. Load it now if this is the first
        // time streaming is used or if a different model was just selected.
        if !isStreamingModelLoaded {
            Task {
                await loadStreamingModel()
            }
            // Proceed — the loop will fire after the model loads (it checks on each step).
        }

        streamingCommittedWords = []
        streamingPreviousWords = []
        streamingPromptTokens = []

        do {
            try audioCapture.startRecording(deviceUID: settingsStore.selectedMicrophoneUID)
            guard recordingIndicator.show() else {
                _ = audioCapture.stopRecording()
                return
            }
            isRecording = true
            Log.audio.info("Recording started (streaming mode, model: \(self.effectiveStreamingModel.rawValue))")

            streamingLoopTask = Task {
                await streamingLoop()
            }
        } catch {
            Log.audio.error("Failed to start streaming recording: \(error)")
        }
    }

    /// Minimum RMS energy to consider a window as containing speech.
    /// ~-42 dBFS — effective for typical indoor recording environments.
    private static func hasVoiceActivity(_ samples: [Float]) -> Bool {
        guard samples.count > 0 else { return false }
        let sumSq = samples.reduce(0 as Float) { $0 + $1 * $1 }
        return sqrt(sumSq / Float(samples.count)) > 0.008
    }

    private func streamingLoop() async {
        var isFirstIteration = true

        while !Task.isCancelled {
            let stepMs = isFirstIteration ? streamFirstStepMs : streamStepMs
            let minSamples = stepMs * 16  // 16 samples per ms at 16 kHz

            try? await Task.sleep(for: .milliseconds(stepMs))
            guard !Task.isCancelled else { break }

            let window = audioCapture.getWindow(
                lengthMs: streamLengthMs,
                keepMs: Self.streamKeepMs
            )
            guard window.count >= minSamples else { continue }

            // Skip silent windows — resets LocalAgreement so the next
            // voiced window is treated as a fresh first iteration.
            guard Self.hasVoiceActivity(window) else {
                if !isFirstIteration {
                    streamingPreviousWords = []
                    isFirstIteration = true
                }
                continue
            }

            isFirstIteration = false

            let language = settingsStore.selectedLanguage
            let langStr = language == .auto ? "auto" : language.rawValue

            // Wait for the streaming model to finish loading if it was just triggered.
            guard isStreamingModelLoaded else { continue }

            let text: String
            let tokens: [Int32]
            do {
                (text, tokens) = try await streamingEngine.transcribeWindow(
                    samples: window,
                    language: langStr,
                    promptTokens: streamingPromptTokens
                )
            } catch {
                Log.whisper.error("Streaming transcription failed: \(error)")
                continue
            }

            guard !Task.isCancelled else { break }

            let currentWords = Self.splitIntoWords(text)
            guard !currentWords.isEmpty else {
                streamingPreviousWords = []
                continue
            }

            // LocalAgreement: compute how many leading words are stable across windows.
            // On the very first voiced window there is no previous transcription to compare
            // against, so we speculatively commit the first half of decoded words immediately.
            // The second window then confirms or overwrites — validated by Macháček et al.
            // (arXiv:2307.14743) who show first-window accuracy >85% at ≤1 s chunk sizes.
            let stableCount: Int
            if streamingPreviousWords.isEmpty {
                stableCount = max(1, currentWords.count / 2)
            } else {
                // When the sliding window advances it drops old words from the front.
                // Find how many words were dropped from `streamingPreviousWords` so we
                // compare overlapping regions rather than position 0 vs position 0.
                let shift = Self.findWindowShift(from: streamingPreviousWords, to: currentWords)
                let alignedPrevious = Array(streamingPreviousWords.dropFirst(shift))
                stableCount = Self.longestCommonWordPrefix(currentWords, alignedPrevious)
            }
            streamingPreviousWords = currentWords

            guard stableCount > 0 else { continue }

            // Find how many of currentWords were already committed (typed) in a prior iteration.
            let alreadyTyped = Self.findAlignedTypedCount(
                committed: streamingCommittedWords,
                current: currentWords
            )

            if stableCount > alreadyTyped {
                let newWords = Array(currentWords[alreadyTyped..<stableCount])
                let prefix = streamingCommittedWords.isEmpty ? "" : " "
                let newText = prefix + newWords.joined(separator: " ")
                Log.whisper.info("Streaming text: \(newText, privacy: .private)")
                await TextInjector.typeText(newText)
                streamingCommittedWords.append(contentsOf: newWords)
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

        defer {
            streamingCommittedWords = []
            streamingPreviousWords = []
            streamingPromptTokens = []
            isProcessing = false
            recordingIndicator.hide()
        }

        // Final pass: transcribe only the last streamLengthMs of audio so it's fast.
        // This catches trailing words the streaming loop hadn't confirmed yet.
        let language = settingsStore.selectedLanguage
        let langStr = language == .auto ? "auto" : language.rawValue
        let finalWindow = samples.count > streamLengthMs * 16
            ? Array(samples.suffix(streamLengthMs * 16))
            : samples
        do {
            let (finalText, _) = try await streamingEngine.transcribeWindow(
                samples: finalWindow,
                language: langStr,
                promptTokens: streamingPromptTokens
            )
            let finalWords = Self.splitIntoWords(finalText)

            let alreadyTyped = Self.findAlignedTypedCount(
                committed: streamingCommittedWords,
                current: finalWords
            )

            if finalWords.count > alreadyTyped {
                let remaining = Array(finalWords[alreadyTyped...])
                let prefix = streamingCommittedWords.isEmpty ? "" : " "
                let remainingText = prefix + remaining.joined(separator: " ")
                if !remainingText.isEmpty {
                    Log.whisper.info("Streaming final: \(remainingText, privacy: .private)")
                    await TextInjector.typeText(remainingText)
                }
            } else if streamingCommittedWords.isEmpty && !finalText.isEmpty {
                Log.whisper.info("Streaming fallback: \(finalText, privacy: .private)")
                await TextInjector.typeText(finalText)
            }
        } catch {
            Log.whisper.error("Streaming final transcription failed: \(error)")
            showPermissionError("Transcription failed: \(error.localizedDescription)")
        }
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

    /// When the sliding window advances it drops words from the front of the previous
    /// transcription. This finds how many words were dropped so we can compare the
    /// overlapping region rather than misaligned position 0s.
    ///
    /// Returns the number of words to skip from the start of `previous` to align it
    /// with `current`. Returns `previous.count` when no overlap is found.
    private static func findWindowShift(from previous: [String], to current: [String]) -> Int {
        guard !previous.isEmpty, !current.isEmpty else { return 0 }
        let verifyLen = min(3, min(previous.count, current.count))
        for shift in 0..<previous.count {
            let tail = previous.dropFirst(shift)
            let matchLen = min(verifyLen, min(tail.count, current.count))
            guard matchLen > 0 else { break }
            if tail.prefix(matchLen).elementsEqual(current.prefix(matchLen)) {
                return shift
            }
        }
        return previous.count
    }

    /// Find how many words at the START of `current` were already committed in a prior
    /// iteration (handles the case where the window slid so committed words no longer
    /// start at index 0 of the new transcription).
    ///
    /// Returns the number of `current` words that should be skipped because they
    /// were already typed.
    private static func findAlignedTypedCount(committed: [String], current: [String]) -> Int {
        guard !committed.isEmpty, !current.isEmpty else { return 0 }
        let maxCheck = min(committed.count, current.count)
        for k in stride(from: maxCheck, through: 1, by: -1) {
            if committed.suffix(k).elementsEqual(current.prefix(k)) {
                return k
            }
        }
        return 0
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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "Meeting Transcript Ready"
            content.body = "Saved to \(fileURL.lastPathComponent)"
            content.sound = .default
            content.userInfo = ["fileURL": fileURL.absoluteString]

            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
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
