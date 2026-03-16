import CSherpaOnnx
import Foundation
import OSLog

/// A speaker segment identified by the diarization process.
struct SpeakerSegment {
    let start: Double
    let end: Double
    let speaker: String
}

/// Errors that can occur during speaker diarization.
enum DiarizationError: Error, LocalizedError {
    case failedToCreateDiarizer
    case failedToReadWAV(String)
    case failedToProcess
    case sampleRateMismatch(expected: Int32, got: Int)

    var errorDescription: String? {
        switch self {
        case .failedToCreateDiarizer:
            return "Failed to create sherpa-onnx diarizer — check model paths"
        case .failedToReadWAV(let detail):
            return "Failed to read WAV file: \(detail)"
        case .failedToProcess:
            return "Diarization processing returned no result"
        case .sampleRateMismatch(let expected, let got):
            return "Sample rate mismatch: model expects \(expected) Hz, WAV has \(got) Hz"
        }
    }
}

/// Actor wrapping sherpa-onnx's C API for offline speaker diarization.
actor SherpaOnnxDiarizer {
    static let shared = SherpaOnnxDiarizer()
    private init() {}

    /// Run speaker diarization on a 16 kHz mono Float32 WAV file.
    ///
    /// - Parameters:
    ///   - wavPath: Path to the WAV file (IEEE Float32, 16 kHz, mono, 44-byte header).
    ///   - segmentationModelPath: Path to the pyannote segmentation ONNX model.
    ///   - embeddingModelPath: Path to the speaker embedding ONNX model.
    /// - Returns: Array of speaker segments sorted by start time.
    func diarize(
        wavPath: String,
        segmentationModelPath: String,
        embeddingModelPath: String
    ) throws -> [SpeakerSegment] {
        Log.meeting.info("Starting diarization for: \(wavPath)")

        // Read WAV samples (IEEE Float32, 16 kHz, mono — 44-byte header)
        let samples = try readWAVSamples(path: wavPath)
        Log.meeting.info("Read \(samples.count) samples from WAV (\(String(format: "%.1f", Double(samples.count) / 16000.0))s)")

        // Use nested withCString closures to keep all C strings alive during the C API calls.
        let segments: [SpeakerSegment] = try segmentationModelPath.withCString { segModelCStr in
            try embeddingModelPath.withCString { embModelCStr in
                try "cpu".withCString { providerCStr in

                    // Build config
                    var config = SherpaOnnxOfflineSpeakerDiarizationConfig()

                    // Segmentation model
                    config.segmentation.pyannote.model = segModelCStr
                    config.segmentation.num_threads = 4
                    config.segmentation.debug = 0
                    config.segmentation.provider = providerCStr

                    // Embedding model
                    config.embedding.model = embModelCStr
                    config.embedding.num_threads = 4
                    config.embedding.debug = 0
                    config.embedding.provider = providerCStr

                    // Clustering
                    config.clustering.num_clusters = 0  // Use threshold instead
                    config.clustering.threshold = 0.5

                    // Duration filters
                    config.min_duration_on = 0.3
                    config.min_duration_off = 0.5

                    // Create the diarizer
                    guard let sd = SherpaOnnxCreateOfflineSpeakerDiarization(&config) else {
                        throw DiarizationError.failedToCreateDiarizer
                    }
                    defer { SherpaOnnxDestroyOfflineSpeakerDiarization(sd) }

                    // Verify sample rate
                    let expectedRate = SherpaOnnxOfflineSpeakerDiarizationGetSampleRate(sd)
                    let wavRate = 16000
                    guard expectedRate == Int32(wavRate) else {
                        throw DiarizationError.sampleRateMismatch(expected: expectedRate, got: wavRate)
                    }

                    // Process audio
                    Log.meeting.info("Running diarization (\(samples.count) samples, \(expectedRate) Hz)...")
                    guard let result = samples.withUnsafeBufferPointer({ buf in
                        SherpaOnnxOfflineSpeakerDiarizationProcess(sd, buf.baseAddress, Int32(buf.count))
                    }) else {
                        throw DiarizationError.failedToProcess
                    }
                    defer { SherpaOnnxOfflineSpeakerDiarizationDestroyResult(result) }

                    // Extract segments
                    let numSegments = SherpaOnnxOfflineSpeakerDiarizationResultGetNumSegments(result)
                    Log.meeting.info("Diarization found \(numSegments) segments")

                    guard numSegments > 0 else { return [] }

                    guard let rawSegments = SherpaOnnxOfflineSpeakerDiarizationResultSortByStartTime(result) else {
                        return []
                    }
                    defer { SherpaOnnxOfflineSpeakerDiarizationDestroySegment(rawSegments) }

                    var output: [SpeakerSegment] = []
                    output.reserveCapacity(Int(numSegments))

                    for i in 0..<Int(numSegments) {
                        let seg = rawSegments[i]
                        let label = String(format: "SPEAKER_%02d", seg.speaker)
                        output.append(SpeakerSegment(
                            start: Double(seg.start),
                            end: Double(seg.end),
                            speaker: label
                        ))
                    }

                    Log.meeting.info("Diarization complete: \(output.count) segments")
                    return output
                }
            }
        }

        return segments
    }

    // MARK: - Private

    /// Read raw Float32 samples from a WAV file with a 44-byte header.
    private func readWAVSamples(path: String) throws -> [Float] {
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            throw DiarizationError.failedToReadWAV("File not found: \(path)")
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DiarizationError.failedToReadWAV(error.localizedDescription)
        }

        // WAV header is 44 bytes for standard PCM/IEEE float
        let headerSize = 44
        guard data.count > headerSize else {
            throw DiarizationError.failedToReadWAV("WAV file too small (\(data.count) bytes)")
        }

        let sampleData = data.dropFirst(headerSize)
        let sampleCount = sampleData.count / MemoryLayout<Float>.size

        guard sampleCount > 0 else {
            throw DiarizationError.failedToReadWAV("No audio samples in WAV file")
        }

        let samples = sampleData.withUnsafeBytes { rawBuffer in
            let floatBuffer = rawBuffer.bindMemory(to: Float.self)
            return Array(floatBuffer.prefix(sampleCount))
        }

        return samples
    }
}
