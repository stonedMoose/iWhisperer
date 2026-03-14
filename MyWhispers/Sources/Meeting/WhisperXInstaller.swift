import Foundation
import OSLog

actor WhisperXInstaller {
    static let shared = WhisperXInstaller()

    private var envDir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("MyWhispers/whisperx-env")
    }

    var whisperXPath: String {
        envDir.appendingPathComponent("bin/whisperx").path
    }

    var pythonPath: String {
        envDir.appendingPathComponent("bin/python3").path
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: whisperXPath)
    }

    func install(onStatus: @escaping @Sendable (String) -> Void) async throws {
        if isInstalled { return }

        // Find python3
        let pythonPath = try findPython()

        onStatus("Creating Python environment...")
        try await runProcess(pythonPath, arguments: ["-m", "venv", envDir.path])

        let pip = envDir.appendingPathComponent("bin/pip").path
        onStatus("Installing WhisperX (this may take a few minutes)...")
        try await runProcess(pip, arguments: ["install", "whisperx==3.1.6", "--no-cache-dir"])

        guard isInstalled else {
            throw WhisperXError.installFailed("whisperx binary not found after installation")
        }

        Log.meeting.info("WhisperX installed successfully")
    }

    private func findPython() throws -> String {
        let candidates = ["/usr/bin/python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3"]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        // Try which
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !output.isEmpty else {
            throw WhisperXError.pythonNotFound
        }
        return output
    }

    private func runProcess(_ path: String, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardError = errorPipe

            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    continuation.resume(throwing: WhisperXError.installFailed(stderr))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum WhisperXError: LocalizedError {
    case pythonNotFound
    case installFailed(String)
    case missingHFToken
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            "Python 3 not found. Please install Python via Homebrew (brew install python) or python.org."
        case .installFailed(let detail):
            "WhisperX installation failed: \(detail)"
        case .missingHFToken:
            "HuggingFace token is required for speaker diarization. Set it in Settings > Meeting."
        case .transcriptionFailed(let detail):
            "Meeting transcription failed: \(detail)"
        }
    }
}
