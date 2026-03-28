import CWhisper
import Foundation
import OSLog

actor WhisperCppEngine {
    static let shared = WhisperCppEngine()

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
    /// Throws on failure or timeout (default 120s).
    func transcribe(samples: [Float], language: String, timeout: Duration = .seconds(120)) async throws -> String {
        guard let ctx else { throw WhisperCppError.notLoaded }

        let maxThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        var params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
        params.beam_search.beam_size = 5
        params.print_realtime = false
        params.print_progress = false
        params.print_special = false
        params.print_timestamps = false
        params.translate = false
        params.single_segment = false
        params.no_context = true
        params.n_threads = Int32(maxThreads)
        params.no_speech_thold = 0.6

        let lang = language == "auto" ? nil : language
        let result: Int32 = try await withThrowingTimeout(timeout) {
            lang.withOptionalCString { langPtr in
                params.language = langPtr
                return samples.withUnsafeBufferPointer { samplesPtr in
                    whisper_full(ctx, params, samplesPtr.baseAddress, Int32(samplesPtr.count))
                }
            }
        }

        guard result == 0 else {
            throw WhisperCppError.inferenceFailed(result)
        }

        return collectSegmentText()
    }

    /// Transcribe a sliding window of audio, returning text and token IDs for prompt context.
    /// Throws on failure or timeout (default 30s for streaming windows).
    func transcribeWindow(samples: [Float], language: String,
                          promptTokens: [whisper_token], timeout: Duration = .seconds(30)) async throws -> (text: String, tokens: [whisper_token]) {
        guard let ctx else { throw WhisperCppError.notLoaded }

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
        params.no_speech_thold = 0.6

        let lang = language == "auto" ? nil : language

        let maxPromptTokens = Int(whisper_n_text_ctx(ctx)) / 2
        let cappedTokens = promptTokens.count > maxPromptTokens
            ? Array(promptTokens.suffix(maxPromptTokens))
            : promptTokens

        let result: Int32 = try await withThrowingTimeout(timeout) {
            lang.withOptionalCString { langPtr in
                params.language = langPtr

                // Feed prompt tokens for cross-chunk coherence
                return cappedTokens.withUnsafeBufferPointer { promptPtr in
                    if !cappedTokens.isEmpty {
                        params.prompt_tokens = promptPtr.baseAddress
                        params.prompt_n_tokens = Int32(promptPtr.count)
                    }
                    return samples.withUnsafeBufferPointer { samplesPtr in
                        whisper_full(ctx, params, samplesPtr.baseAddress, Int32(samplesPtr.count))
                    }
                }
            }
        }

        guard result == 0 else {
            throw WhisperCppError.inferenceFailed(result)
        }

        let text = collectSegmentText()
        let tokens = collectTokenIds()
        return (text, tokens)
    }

    /// Transcribe audio and return segments with timestamps for diarization merging.
    func transcribeWithSegments(samples: [Float], language: String?, timeout: Duration = .seconds(120)) async throws -> [(start: Double, end: Double, text: String)] {
        guard let ctx else { throw WhisperCppError.notLoaded }

        let maxThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        var params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
        params.beam_search.beam_size = 5
        params.print_realtime = false
        params.print_progress = false
        params.print_special = false
        params.print_timestamps = true
        params.translate = false
        params.single_segment = false
        params.no_context = true
        params.n_threads = Int32(maxThreads)
        params.no_speech_thold = 0.6

        let result: Int32 = try await withThrowingTimeout(timeout) {
            language.withOptionalCString { langPtr in
                params.language = langPtr
                return samples.withUnsafeBufferPointer { samplesPtr in
                    whisper_full(ctx, params, samplesPtr.baseAddress, Int32(samplesPtr.count))
                }
            }
        }

        guard result == 0 else {
            throw WhisperCppError.inferenceFailed(result)
        }

        var segments: [(start: Double, end: Double, text: String)] = []
        let nSegments = whisper_full_n_segments(ctx)
        for i in 0..<nSegments {
            let t0 = whisper_full_get_segment_t0(ctx, i)  // in centiseconds (100ths of second)
            let t1 = whisper_full_get_segment_t1(ctx, i)
            guard let cStr = whisper_full_get_segment_text(ctx, i) else { continue }
            let text = cleanText(String(cString: cStr))
            guard !text.isEmpty else { continue }
            segments.append((
                start: Double(t0) / 100.0,
                end: Double(t1) / 100.0,
                text: text
            ))
        }
        return segments
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
    case notLoaded
    case inferenceFailed(Int32)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path): "Failed to load whisper model at: \(path)"
        case .notLoaded: "Whisper model is not loaded"
        case .inferenceFailed(let code): "Transcription failed (error code \(code))"
        case .timedOut: "Transcription timed out"
        }
    }
}

/// Run a synchronous closure with a timeout, throwing `.timedOut` if exceeded.
private func withThrowingTimeout<T: Sendable>(_ duration: Duration, operation: @escaping @Sendable () -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw WhisperCppError.timedOut
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
