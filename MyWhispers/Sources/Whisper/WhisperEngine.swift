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
