import CWhisper
import Foundation
import OSLog

actor WhisperCppEngine {
    private var ctx: OpaquePointer?
    private var currentModelPath: String?

    var isLoaded: Bool { ctx != nil }

    /// Load a GGML model from the given file path.
    func loadModel(path: String) throws {
        unloadModel()

        var params = whisper_context_default_params()
        params.use_gpu = true
        params.flash_attn = true

        guard let context = whisper_init_from_file_with_params(path, params) else {
            throw WhisperCppError.modelLoadFailed(path)
        }

        ctx = context
        currentModelPath = path
        Log.whisper.info("whisper.cpp model loaded: \(path)")
    }

    /// Unload the current model and free resources.
    func unloadModel() {
        if let ctx {
            whisper_free(ctx)
        }
        ctx = nil
        currentModelPath = nil
    }

    deinit {
        if let ctx {
            whisper_free(ctx)
        }
    }

    /// Transcribe audio samples (16kHz Float32) to text.
    func transcribe(samples: [Float], language: String) -> String {
        guard let ctx else { return "" }

        let maxThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_special = false
        params.print_timestamps = false
        params.translate = false
        params.single_segment = false
        params.no_context = true
        params.n_threads = Int32(maxThreads)

        let lang = language == "auto" ? nil : language
        let result: Int32 = lang.withOptionalCString { langPtr in
            params.language = langPtr
            return samples.withUnsafeBufferPointer { samplesPtr in
                whisper_full(ctx, params, samplesPtr.baseAddress, Int32(samplesPtr.count))
            }
        }

        guard result == 0 else {
            Log.whisper.error("whisper_full failed with code \(result)")
            return ""
        }

        return collectSegmentText()
    }

    /// Transcribe a sliding window of audio, returning text and token IDs for prompt context.
    func transcribeWindow(samples: [Float], language: String,
                          promptTokens: [whisper_token]) -> (text: String, tokens: [whisper_token]) {
        guard let ctx else { return ("", []) }

        let maxThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_special = false
        params.print_timestamps = false
        params.translate = false
        params.single_segment = true
        params.no_context = promptTokens.isEmpty
        params.n_threads = Int32(maxThreads)
        params.no_timestamps = true

        let lang = language == "auto" ? nil : language

        let result: Int32 = lang.withOptionalCString { langPtr in
            params.language = langPtr

            // Feed prompt tokens for cross-chunk coherence
            return promptTokens.withUnsafeBufferPointer { promptPtr in
                if !promptTokens.isEmpty {
                    params.prompt_tokens = promptPtr.baseAddress
                    params.prompt_n_tokens = Int32(promptPtr.count)
                }
                return samples.withUnsafeBufferPointer { samplesPtr in
                    whisper_full(ctx, params, samplesPtr.baseAddress, Int32(samplesPtr.count))
                }
            }
        }

        guard result == 0 else {
            Log.whisper.error("whisper_full (window) failed with code \(result)")
            return ("", [])
        }

        let text = collectSegmentText()
        let tokens = collectTokenIds()
        return (text, tokens)
    }

    // MARK: - Private

    private func collectSegmentText() -> String {
        guard let ctx else { return "" }
        var text = ""
        let nSegments = whisper_full_n_segments(ctx)
        for i in 0..<nSegments {
            if let cStr = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: cStr)
            }
        }
        return cleanText(text)
    }

    private func collectTokenIds() -> [whisper_token] {
        guard let ctx else { return [] }
        var tokens: [whisper_token] = []
        let nSegments = whisper_full_n_segments(ctx)
        for i in 0..<nSegments {
            let nTokens = whisper_full_n_tokens(ctx, i)
            for j in 0..<nTokens {
                let tokenId = whisper_full_get_token_id(ctx, i, j)
                tokens.append(tokenId)
            }
        }
        return tokens
    }

    /// Remove Whisper special tokens like <|en|>, <|transcribe|>, etc.
    private func cleanText(_ text: String) -> String {
        text.replacingOccurrences(
            of: "<\\|[^|]*\\|>",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Helper

private extension Optional where Wrapped == String {
    func withOptionalCString<R>(_ body: (UnsafePointer<CChar>?) -> R) -> R {
        switch self {
        case .some(let string):
            return string.withCString { body($0) }
        case .none:
            return body(nil)
        }
    }
}

enum WhisperCppError: LocalizedError {
    case modelLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path): "Failed to load whisper model at: \(path)"
        }
    }
}
