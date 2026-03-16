import CWhisper
import Foundation

actor WhisperCppEngine {
    private var ctx: OpaquePointer?

    var isLoaded: Bool { ctx != nil }

    func loadModel(path: String) throws {
        unloadModel()

        var params = whisper_context_default_params()
        params.use_gpu = true
        params.flash_attn = true

        guard let context = whisper_init_from_file_with_params(path, params) else {
            throw WhisperError.modelLoadFailed(path)
        }

        ctx = context
        Log.whisper.info("Model loaded: \(path)")
    }

    func unloadModel() {
        if let ctx { whisper_free(ctx) }
        ctx = nil
    }

    deinit {
        if let ctx { whisper_free(ctx) }
    }

    func transcribe(samples: [Float], language: String) -> String {
        guard let ctx else { return "" }

        let maxThreads = max(1, min(4, ProcessInfo.processInfo.processorCount - 1))
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
        let result: Int32 = lang.withOptionalCString { langPtr in
            params.language = langPtr
            return samples.withUnsafeBufferPointer { samplesPtr in
                whisper_full(ctx, params, samplesPtr.baseAddress, Int32(samplesPtr.count))
            }
        }

        guard result == 0 else {
            Log.whisper.error("whisper_full failed: \(result)")
            return ""
        }

        return collectSegmentText()
    }

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

    private func cleanText(_ text: String) -> String {
        text.replacingOccurrences(
            of: "<\\|[^|]*\\|>",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
    }
}

private extension Optional where Wrapped == String {
    func withOptionalCString<R>(_ body: (UnsafePointer<CChar>?) -> R) -> R {
        switch self {
        case .some(let string): string.withCString { body($0) }
        case .none: body(nil)
        }
    }
}

enum WhisperError: LocalizedError {
    case modelLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path): "Failed to load whisper model at: \(path)"
        }
    }
}
