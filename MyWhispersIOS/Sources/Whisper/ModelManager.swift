import Foundation

actor ModelManager {
    static let shared = ModelManager()

    func ensureModel(_ model: WhisperModel, progress: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        let path = modelPath(for: model)

        if FileManager.default.fileExists(atPath: path) {
            Log.whisper.info("Model cached: \(path)")
            progress?(1.0)
            return path
        }

        let dir = modelsDirectory
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        Log.whisper.info("Downloading \(model.rawValue)...")

        let delegate = DownloadDelegate(progressCallback: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (tempURL, response) = try await session.download(from: model.downloadURL, delegate: delegate)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ModelManagerError.downloadFailed(model.rawValue)
        }

        try FileManager.default.moveItem(atPath: tempURL.path, toPath: path)
        Log.whisper.info("Model saved: \(path)")
        return path
    }

    func modelPath(for model: WhisperModel) -> String {
        modelsDirectory + "/ggml-\(model.ggmlName).bin"
    }

    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(for: model))
    }

    func deleteModel(_ model: WhisperModel) throws {
        let path = modelPath(for: model)
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
    }

    func modelFileSize(_ model: WhisperModel) -> Int64? {
        let path = modelPath(for: model)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else { return nil }
        return size
    }

    private var modelsDirectory: String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("models").path
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progressCallback: (@Sendable (Double) -> Void)?

    init(progressCallback: (@Sendable (Double) -> Void)?) {
        self.progressCallback = progressCallback
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressCallback?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}

enum ModelManagerError: LocalizedError {
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let model): "Failed to download model: \(model)"
        }
    }
}
