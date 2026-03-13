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
