import OSLog

enum Log {
    static let whisper = Logger(subsystem: Bundle.main.bundleIdentifier ?? "iWhisperer", category: "whisper")
    static let audio = Logger(subsystem: Bundle.main.bundleIdentifier ?? "iWhisperer", category: "audio")
    static let app = Logger(subsystem: Bundle.main.bundleIdentifier ?? "iWhisperer", category: "app")
}
