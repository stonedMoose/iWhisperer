import Foundation
import OSLog

actor ModelManager {
    static let shared = ModelManager()

    private var downloadTask: URLSessionDownloadTask?
    private var progressContinuation: AsyncStream<Double>.Continuation?

    /// Download a GGML model from HuggingFace if not already cached.
    /// Returns the local file path.
    func ensureModel(_ model: WhisperModel, progressCallback: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        let path = modelPath(for: model)

        if FileManager.default.fileExists(atPath: path) {
            Log.whisper.info("Model already cached: \(path)")
            progressCallback?(1.0)
            return path
        }

        let dir = modelsDirectory
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let url = model.downloadURL
        Log.whisper.info("Downloading model from \(url.absoluteString)")

        let delegate = DownloadDelegate(progressCallback: progressCallback)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (tempURL, response) = try await session.download(from: url, delegate: delegate)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ModelManagerError.downloadFailed(model.rawValue)
        }

        try FileManager.default.moveItem(atPath: tempURL.path, toPath: path)
        Log.whisper.info("Model downloaded to \(path)")
        return path
    }

    func modelPath(for model: WhisperModel) -> String {
        modelsDirectory + "/ggml-\(model.ggmlName).bin"
    }

    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(for: model))
    }

    // MARK: - Diarization models

    enum DiarizationModel: String {
        case embedding = "speaker-embedding"
        case segmentation = "speaker-segmentation"

        var filename: String {
            switch self {
            case .embedding: "3dspeaker_speech_eres2net_large_sv_zh-cn_3dspeaker_16k.onnx"
            case .segmentation: "pyannote-segmentation-3-0.onnx"
            }
        }

        var downloadURL: URL {
            switch self {
            case .embedding:
                URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/3dspeaker_speech_eres2net_large_sv_zh-cn_3dspeaker_16k.onnx")!
            case .segmentation:
                URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2")!
            }
        }

        /// Whether the download is an archive that needs extraction.
        var isArchive: Bool {
            switch self {
            case .embedding: false
            case .segmentation: true
            }
        }

        /// The filename inside the archive (if isArchive).
        var archiveModelPath: String {
            "sherpa-onnx-pyannote-segmentation-3-0/model.onnx"
        }

        var displayName: String {
            switch self {
            case .embedding: "Speaker embedding model (~90 MB)"
            case .segmentation: "Speaker segmentation model (~6 MB)"
            }
        }
    }

    func ensureDiarizationModel(_ model: DiarizationModel, progressCallback: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        let path = diarizationModelPath(for: model)

        if FileManager.default.fileExists(atPath: path) {
            Log.whisper.info("Diarization model already cached: \(path)")
            progressCallback?(1.0)
            return path
        }

        let dir = modelsDirectory
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let url = model.downloadURL
        Log.whisper.info("Downloading diarization model from \(url.absoluteString)")

        let delegate = DownloadDelegate(progressCallback: progressCallback)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (tempURL, response) = try await session.download(from: url, delegate: delegate)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ModelManagerError.downloadFailed(model.rawValue)
        }

        if model.isArchive {
            // Extract .tar.bz2 archive, then copy the model file out
            let extractDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("sherpa-extract-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: extractDir) }

            // Move archive to a .tar.bz2 path so tar can handle it
            let archivePath = extractDir.appendingPathComponent("archive.tar.bz2")
            try FileManager.default.moveItem(atPath: tempURL.path, toPath: archivePath.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["xjf", archivePath.path, "-C", extractDir.path]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw ModelManagerError.downloadFailed("Failed to extract \(model.rawValue) archive")
            }

            let extractedModel = extractDir.appendingPathComponent(model.archiveModelPath)
            guard FileManager.default.fileExists(atPath: extractedModel.path) else {
                throw ModelManagerError.downloadFailed("Model file not found in archive: \(model.archiveModelPath)")
            }

            try FileManager.default.moveItem(atPath: extractedModel.path, toPath: path)
        } else {
            try FileManager.default.moveItem(atPath: tempURL.path, toPath: path)
        }

        Log.whisper.info("Diarization model downloaded to \(path)")
        return path
    }

    func diarizationModelPath(for model: DiarizationModel) -> String {
        modelsDirectory + "/\(model.filename)"
    }

    func isDiarizationModelDownloaded(_ model: DiarizationModel) -> Bool {
        FileManager.default.fileExists(atPath: diarizationModelPath(for: model))
    }

    private var modelsDirectory: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MyWhispers/models").path
    }
}

// MARK: - Download delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progressCallback: (@Sendable (Double) -> Void)?

    init(progressCallback: (@Sendable (Double) -> Void)?) {
        self.progressCallback = progressCallback
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressCallback?(progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // handled by the async download call
    }
}

enum ModelManagerError: LocalizedError {
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let model): "Failed to download model: \(model)"
        }
    }
}
