import AVFoundation
import SwiftData
import SwiftUI
import UIKit

enum TranscriptionState: Equatable {
    case idle
    case recording(elapsed: TimeInterval)
    case transcribing
    case done(text: String)
    case error(message: String)
}

@Observable
@MainActor
final class TranscriptionEngine {
    var state: TranscriptionState = .idle
    var isModelLoaded = false
    var isDownloadingModel = false
    var downloadProgress: Double = 0
    var micPermissionGranted = false

    private let whisperEngine = WhisperCppEngine()
    private let modelManager = ModelManager.shared
    private let audioCapture = AudioCapture()
    private var timerTask: Task<Void, Never>?
    private var recordingStartTime: Date?
    private var modelContext: ModelContext?

    var selectedModel: WhisperModel {
        get { WhisperModel(rawValue: UserDefaults.standard.string(forKey: "selectedModel") ?? "base") ?? .base }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "selectedModel") }
    }

    var selectedLanguage: WhisperLanguage {
        get { WhisperLanguage(rawValue: UserDefaults.standard.string(forKey: "selectedLanguage") ?? "auto") ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "selectedLanguage") }
    }

    var autoCopy: Bool {
        get { UserDefaults.standard.object(forKey: "autoCopy") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoCopy") }
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Setup

    func setup() async {
        await checkMicPermission()
        await loadModel()
    }

    func checkMicPermission() async {
        let status = AVAudioApplication.shared.recordPermission
        switch status {
        case .undetermined:
            micPermissionGranted = await AudioCapture.requestPermission()
        case .granted:
            micPermissionGranted = true
        case .denied:
            micPermissionGranted = false
        @unknown default:
            micPermissionGranted = false
        }
    }

    func loadModel() async {
        let model = selectedModel
        isDownloadingModel = true
        downloadProgress = 0

        do {
            let path = try await modelManager.ensureModel(model) { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            }
            try await whisperEngine.loadModel(path: path)
            isModelLoaded = true
            isDownloadingModel = false
            Log.whisper.info("Model ready")
        } catch {
            isDownloadingModel = false
            state = .error(message: error.localizedDescription)
            Log.whisper.error("Model load failed: \(error)")
        }
    }

    // MARK: - Recording toggle

    func toggleRecording() {
        switch state {
        case .idle, .done, .error:
            startRecording()
        case .recording:
            Task { await stopAndTranscribe() }
        case .transcribing:
            break
        }
    }

    private func startRecording() {
        guard isModelLoaded, micPermissionGranted else {
            state = .error(message: "Model not loaded or mic not granted")
            return
        }

        do {
            try audioCapture.startRecording()
            recordingStartTime = Date()
            state = .recording(elapsed: 0)

            timerTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled, let start = self.recordingStartTime else { break }
                    self.state = .recording(elapsed: Date().timeIntervalSince(start))
                }
            }

            Log.audio.info("Recording started")
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    private func stopAndTranscribe() async {
        timerTask?.cancel()
        timerTask = nil

        let duration = audioCapture.duration
        let samples = audioCapture.stopRecording()
        Log.audio.info("Recording stopped: \(samples.count) samples")

        guard !samples.isEmpty else {
            state = .idle
            return
        }

        state = .transcribing

        let langStr = selectedLanguage == .auto ? "auto" : selectedLanguage.rawValue
        let text = await whisperEngine.transcribe(samples: samples, language: langStr)

        if text.isEmpty {
            state = .error(message: "No speech detected")
            return
        }

        // Save to history
        if let ctx = modelContext {
            let transcription = Transcription(
                text: text,
                language: selectedLanguage.displayName,
                model: selectedModel.rawValue,
                duration: duration
            )
            ctx.insert(transcription)
        }

        // Auto-copy to clipboard
        if autoCopy {
            UIPasteboard.general.string = text
        }

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        state = .done(text: text)
        Log.whisper.info("Transcription complete")
    }
}
