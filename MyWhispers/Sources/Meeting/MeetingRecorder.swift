import AppKit
import Foundation
import OSLog

@MainActor
final class MeetingRecorder {
    private let audioCapture: AudioCapture
    private let settingsStore: SettingsStore
    private var wavWriter: WAVWriter?
    private var recordingStartDate: Date?
    private var transcriptionProcess: Process?
    private var currentOutputDir: URL?

    init(audioCapture: AudioCapture, settingsStore: SettingsStore) {
        self.audioCapture = audioCapture
        self.settingsStore = settingsStore
    }

    var isRecording: Bool { wavWriter != nil }

    func startRecording() throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "meeting-\(formatter.string(from: Date())).wav"
        let url = support.appendingPathComponent("MyWhispers/recordings/\(filename)")

        let writer = try WAVWriter(url: url)
        self.wavWriter = writer
        self.recordingStartDate = Date()

        audioCapture.setOnSamples { samples in
            writer.writeSamples(samples)
        }
        audioCapture.setAccumulateBuffer(false)

        try audioCapture.startRecording()
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

    func transcribe(wavURL: URL) async throws -> String {
        let installer = WhisperXInstaller.shared

        guard await installer.isInstalled else {
            throw WhisperXError.installFailed("WhisperX is not installed")
        }

        let hfToken = settingsStore.hfToken
        guard !hfToken.isEmpty else {
            throw WhisperXError.missingHFToken
        }

        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mywhispers-meeting-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        currentOutputDir = outputDir

        let pythonPath = await installer.pythonPath
        let model = settingsStore.selectedModel.rawValue
        let language = settingsStore.selectedLanguage
        let langArg = language == .auto ? nil : language.rawValue

        defer {
            try? FileManager.default.removeItem(at: wavURL)
            currentOutputDir = nil
        }

        var whisperXArgs = [
            wavURL.path,
            "--model", model,
            "--device", Self.isAppleSilicon ? "mps" : "cpu",
            "--compute_type", Self.isAppleSilicon ? "float16" : "int8",
            "--diarize",
            "--output_format", "json",
            "--output_dir", outputDir.path
        ]
        if let lang = langArg {
            whisperXArgs.append(contentsOf: ["--language", lang])
        }

        // Write a wrapper script that patches torch.load before running whisperx
        // (PyTorch 2.6 changed weights_only default to True, breaking pyannote model loading)
        let scriptURL = outputDir.appendingPathComponent("run_whisperx.py")
        let script = """
        import torch
        _original_load = torch.load
        def _patched_load(*args, **kwargs):
            kwargs['weights_only'] = False
            return _original_load(*args, **kwargs)
        torch.load = _patched_load
        from whisperx.__main__ import cli
        cli()
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        Log.meeting.info("Running WhisperX via Python: \(pythonPath)")

        let (exitCode, stderr): (Int32, String)
        do {
            (exitCode, stderr) = try await withThrowingTaskGroup(of: (Int32, String).self) { group in
                group.addTask {
                    try await self.runWhisperX(
                        path: pythonPath,
                        arguments: [scriptURL.path] + whisperXArgs,
                        hfToken: hfToken
                    )
                }
                group.addTask { @MainActor in
                    try await Task.sleep(for: .seconds(3600))
                    self.transcriptionProcess?.terminate()
                    throw WhisperXError.transcriptionFailed("Timed out after 1 hour")
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        } catch {
            try? FileManager.default.removeItem(at: outputDir)
            throw error
        }

        guard exitCode == 0 else {
            try? FileManager.default.removeItem(at: outputDir)
            throw WhisperXError.transcriptionFailed(stderr)
        }

        // Find the JSON output file
        let jsonFiles = try FileManager.default.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        guard let jsonFile = jsonFiles.first else {
            try? FileManager.default.removeItem(at: outputDir)
            throw WhisperXError.transcriptionFailed("No JSON output file found")
        }

        let jsonData = try Data(contentsOf: jsonFile)
        let markdown = try formatAsMarkdown(jsonData: jsonData, startDate: recordingStartDate ?? Date())

        // Clean up temp dir
        try? FileManager.default.removeItem(at: outputDir)

        return markdown
    }

    /// Transcribe using whisper.cpp + sherpa-onnx native diarization.
    func transcribeBuiltIn(wavURL: URL) async throws -> String {
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
            throw WhisperXError.transcriptionFailed("WAV file too small")
        }
        let sampleData = audioData.dropFirst(44)
        let samples: [Float] = sampleData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }

        let transcriptionSegments = await engine.transcribeWithSegments(
            samples: samples,
            language: language == .auto ? nil : language.rawValue
        )

        guard !transcriptionSegments.isEmpty else {
            throw WhisperXError.transcriptionFailed("Whisper produced no transcription segments")
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
        return formatMergedAsMarkdown(segments: merged, startDate: recordingStartDate ?? Date())
    }

    private func formatMergedAsMarkdown(segments: [TranscriptMerger.MergedSegment], startDate: Date) -> String {
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

    func cancelTranscription() {
        transcriptionProcess?.terminate()
        transcriptionProcess = nil
        if let dir = currentOutputDir {
            try? FileManager.default.removeItem(at: dir)
            currentOutputDir = nil
        }
    }

    // MARK: - Private

    private func runWhisperX(path: String, arguments: [String], hfToken: String) async throws -> (Int32, String) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Int32, String), Error>) in
            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardError = errorPipe
            process.environment = ProcessInfo.processInfo.environment.merging(
                ["HF_TOKEN": hfToken],
                uniquingKeysWith: { _, new in new }
            )
            self.transcriptionProcess = process

            process.terminationHandler = { [weak self] proc in
                let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                Task { @MainActor in
                    self?.transcriptionProcess = nil
                }
                continuation.resume(returning: (proc.terminationStatus, stderr))
            }

            do {
                try process.run()
            } catch {
                self.transcriptionProcess = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private static var isAppleSilicon: Bool {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) == "arm64"
            }
        }
    }

    private func formatAsMarkdown(jsonData: Data, startDate: Date) throws -> String {
        let result = try JSONDecoder().decode(WhisperXResult.self, from: jsonData)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dateStr = dateFormatter.string(from: startDate)

        let duration = elapsedTime
        let durationStr = formatDuration(duration)

        var md = "# Meeting Transcript\n"
        md += "**Date:** \(dateStr)\n"
        md += "**Duration:** \(durationStr)\n\n"
        md += "---\n\n"

        // Merge consecutive segments from same speaker
        var currentSpeaker: String?
        var currentText = ""
        var currentStart: Double = 0

        for segment in result.segments {
            let speaker = segment.speaker ?? "UNKNOWN"

            if speaker == currentSpeaker {
                currentText += " " + segment.text.trimmingCharacters(in: .whitespaces)
            } else {
                // Flush previous
                if let prev = currentSpeaker {
                    md += "**\(prev)** (\(formatTimestamp(currentStart)))\n"
                    md += "\(currentText.trimmingCharacters(in: .whitespaces))\n\n"
                }
                currentSpeaker = speaker
                currentText = segment.text.trimmingCharacters(in: .whitespaces)
                currentStart = segment.start
            }
        }

        // Flush last
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

// MARK: - WhisperX JSON models

struct WhisperXResult: Codable {
    let segments: [WhisperXSegment]
}

struct WhisperXSegment: Codable {
    let start: Double
    let end: Double
    let text: String
    let speaker: String?
}
