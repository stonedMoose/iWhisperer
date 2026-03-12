import Foundation
import WhisperKit

actor WhisperEngine {
    private var whisperKit: WhisperKit?
    private var currentModel: WhisperModel?
    private var streamTranscriber: AudioStreamTranscriber?

    var isLoaded: Bool { whisperKit != nil }

    /// Load (or reload) a Whisper model. Downloads from HuggingFace if not cached.
    func loadModel(_ model: WhisperModel, progressCallback: (@Sendable (Double) -> Void)? = nil) async throws {
        if currentModel == model && whisperKit != nil { return }

        whisperKit = nil
        currentModel = nil

        let modelFolder = Self.modelsDirectory
        try FileManager.default.createDirectory(atPath: modelFolder, withIntermediateDirectories: true)

        // Download model first (with progress tracking) if not already cached
        let downloadedFolder = try await WhisperKit.download(
            variant: model.rawValue,
            downloadBase: URL(fileURLWithPath: modelFolder),
            progressCallback: { progress in
                progressCallback?(progress.fractionCompleted)
            }
        )

        // Load from the downloaded folder
        let config = WhisperKitConfig(
            modelFolder: downloadedFolder.path,
            download: false
        )
        whisperKit = try await WhisperKit(config)
        currentModel = model
    }

    /// Start streaming transcription. Calls `onSegment` on the main actor with confirmed text.
    func startStreaming(language: WhisperLanguage, onStateChange: @escaping @Sendable (AudioStreamTranscriber.State, AudioStreamTranscriber.State) -> Void) async throws {
        guard let whisperKit, let tokenizer = whisperKit.tokenizer else {
            throw WhisperEngineError.modelNotLoaded
        }

        let options = DecodingOptions(
            language: language == .auto ? nil : language.rawValue,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )

        let transcriber = AudioStreamTranscriber(
            audioEncoder: whisperKit.audioEncoder,
            featureExtractor: whisperKit.featureExtractor,
            segmentSeeker: whisperKit.segmentSeeker,
            textDecoder: whisperKit.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: whisperKit.audioProcessor,
            decodingOptions: options,
            requiredSegmentsForConfirmation: 1,
            stateChangeCallback: onStateChange
        )

        streamTranscriber = transcriber
        try await transcriber.startStreamTranscription()
    }

    /// Stop streaming transcription and return any remaining audio samples for final transcription.
    func stopStreaming() async -> [Float] {
        await streamTranscriber?.stopStreamTranscription()
        streamTranscriber = nil

        // Grab audio AFTER stopping so the buffer is complete
        if let audioProcessor = whisperKit?.audioProcessor {
            return Array(audioProcessor.audioSamples)
        }
        return []
    }

    /// ~/Library/Application Support/MyWhispers/models
    private static var modelsDirectory: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MyWhispers/models").path
    }

    /// Transcribe audio samples (16kHz Float array) to text.
    func transcribe(audioSamples: [Float], language: WhisperLanguage) async throws -> String {
        guard let whisperKit else {
            throw WhisperEngineError.modelNotLoaded
        }

        let options = DecodingOptions(
            language: language == .auto ? nil : language.rawValue
        )

        let results: [TranscriptionResult] = try await whisperKit.transcribe(
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
