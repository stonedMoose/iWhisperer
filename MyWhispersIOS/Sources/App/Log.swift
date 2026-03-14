import OSLog

enum Log {
    static let whisper = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MyWhispersIOS", category: "whisper")
    static let audio = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MyWhispersIOS", category: "audio")
    static let app = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MyWhispersIOS", category: "app")
}
