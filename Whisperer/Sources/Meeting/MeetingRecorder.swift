import AppKit
import Foundation
import OSLog

@MainActor
final class MeetingRecorder {
    private let audioCapture: AudioCapture
    private let settingsStore: SettingsStore
    private var wavWriter: WAVWriter?
    private var recordingStartDate: Date?

    init(audioCapture: AudioCapture, settingsStore: SettingsStore) {
        self.audioCapture = audioCapture
        self.settingsStore = settingsStore
    }

    var isRecording: Bool { wavWriter != nil }

    func startRecording() throws {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw MeetingError.directoryUnavailable
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "meeting-\(formatter.string(from: Date())).wav"
        let url = support.appendingPathComponent("Whisperer/recordings/\(filename)")

        let writer = try WAVWriter(url: url)
        self.wavWriter = writer
        self.recordingStartDate = Date()

        audioCapture.setOnSamples { samples in
            writer.writeSamples(samples)
        }
        audioCapture.setAccumulateBuffer(false)

        try audioCapture.startRecording(deviceUID: settingsStore.selectedMicrophoneUID)
        Log.meeting.info("Meeting recording started: \(url.lastPathComponent)")
    }

    func stopRecording() -> URL? {
        audioCapture.setAccumulateBuffer(true)
        _ = audioCapture.stopRecording()

        guard let writer = wavWriter else { return nil }
        do {
            try writer.finalize()
            Log.meeting.info("Meeting WAV finalized: \(writer.url.lastPathComponent)")
        } catch {
            Log.meeting.error("Failed to finalize WAV: \(error)")
            return nil
        }

        wavWriter = nil
        return writer.url
    }

    var elapsedTime: TimeInterval {
        guard let start = recordingStartDate else { return 0 }
        return Date().timeIntervalSince(start)
    }

    /// Transcribe using whisper.cpp + sherpa-onnx native diarization.
    func transcribe(wavURL: URL) async throws -> String {
        defer {
            try? FileManager.default.removeItem(at: wavURL)
        }

        // 1. Ensure diarization models are downloaded
        let segmentationPath = try await ModelManager.shared.ensureDiarizationModel(.segmentation)
        let embeddingPath = try await ModelManager.shared.ensureDiarizationModel(.embedding)

        // 2. Transcribe with whisper.cpp
        let model = settingsStore.selectedModel
        let language = settingsStore.selectedLanguage
        let modelPath = try await ModelManager.shared.ensureModel(model)

        let engine = WhisperCppEngine.shared
        try await engine.loadModel(path: modelPath)

        let audioData = try Data(contentsOf: wavURL)
        guard audioData.count > 44 else {
            throw MeetingError.transcriptionFailed("WAV file too small")
        }
        let sampleData = audioData.dropFirst(44)
        let samples: [Float] = sampleData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }

        let transcriptionSegments = try await engine.transcribeWithSegments(
            samples: samples,
            language: language == .auto ? nil : language.rawValue
        )

        guard !transcriptionSegments.isEmpty else {
            throw MeetingError.transcriptionFailed("Whisper produced no transcription segments")
        }

        // 3. Run sherpa-onnx diarization
        let speakerSegments = try await SherpaOnnxDiarizer.shared.diarize(
            wavPath: wavURL.path,
            segmentationModelPath: segmentationPath,
            embeddingModelPath: embeddingPath
        )

        // 4. Merge transcription with speaker labels
        let merged = TranscriptMerger.merge(
            transcriptionSegments: transcriptionSegments,
            speakerSegments: speakerSegments
        )

        // 5. Format as Markdown
        return formatAsMarkdown(segments: merged, startDate: recordingStartDate ?? Date())
    }

    // MARK: - Private

    private func formatAsMarkdown(segments: [TranscriptMerger.MergedSegment], startDate: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dateStr = dateFormatter.string(from: startDate)

        let duration = elapsedTime
        let durationStr = formatDuration(duration)

        var md = "# Meeting Transcript\n"
        md += "**Date:** \(dateStr)\n"
        md += "**Duration:** \(durationStr)\n\n"
        md += "---\n\n"

        var currentSpeaker: String?
        var currentText = ""
        var currentStart: Double = 0

        for segment in segments {
            if segment.speaker == currentSpeaker {
                currentText += " " + segment.text.trimmingCharacters(in: .whitespaces)
            } else {
                if let prev = currentSpeaker {
                    md += "**\(prev)** (\(formatTimestamp(currentStart)))\n"
                    md += "\(currentText.trimmingCharacters(in: .whitespaces))\n\n"
                }
                currentSpeaker = segment.speaker
                currentText = segment.text.trimmingCharacters(in: .whitespaces)
                currentStart = segment.start
            }
        }

        if let prev = currentSpeaker {
            md += "**\(prev)** (\(formatTimestamp(currentStart)))\n"
            md += "\(currentText.trimmingCharacters(in: .whitespaces))\n"
        }

        return md
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 {
            return "\(h) hour\(h > 1 ? "s" : "") \(m) min"
        }
        return "\(m) minute\(m > 1 ? "s" : "")"
    }
}

enum MeetingError: LocalizedError {
    case transcriptionFailed(String)
    case directoryUnavailable

    var errorDescription: String? {
        switch self {
        case .transcriptionFailed(let detail): "Meeting transcription failed: \(detail)"
        case .directoryUnavailable: "Application Support directory is unavailable"
        }
    }
}
