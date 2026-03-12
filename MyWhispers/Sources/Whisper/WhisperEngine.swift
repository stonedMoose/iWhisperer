import Foundation
import WhisperKit

actor WhisperEngine {
    private var whisperKit: WhisperKit?
    private var currentModel: WhisperModel?

    var isLoaded: Bool { whisperKit != nil }

    /// Load (or reload) a Whisper model. Downloads from HuggingFace if not cached.
    func loadModel(_ model: WhisperModel, progressCallback: (@Sendable (Double) -> Void)? = nil) async throws {
        if currentModel == model && whisperKit != nil { return }

        whisperKit = nil
        currentModel = nil

        let modelFolder = Self.modelsDirectory
        try FileManager.default.createDirectory(atPath: modelFolder, withIntermediateDirectories: true)

        let downloadedFolder = try await WhisperKit.download(
            variant: model.rawValue,
            downloadBase: URL(fileURLWithPath: modelFolder),
            progressCallback: { progress in
                progressCallback?(progress.fractionCompleted)
            }
        )

        let config = WhisperKitConfig(
            modelFolder: downloadedFolder.path,
            download: false
        )
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

        let results: [TranscriptionResult] = try await whisperKit.transcribe(
            audioArray: audioSamples,
            decodeOptions: options
        )

        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// ~/Library/Application Support/MyWhispers/models
    private static var modelsDirectory: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MyWhispers/models").path
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
