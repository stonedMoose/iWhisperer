import OSLog

enum Log {
    static let audio = Logger(subsystem: "com.mywhispers.app", category: "audio")
    static let whisper = Logger(subsystem: "com.mywhispers.app", category: "whisper")
    static let permissions = Logger(subsystem: "com.mywhispers.app", category: "permissions")
    static let general = Logger(subsystem: "com.mywhispers.app", category: "general")
    static let ui = Logger(subsystem: "com.mywhispers.app", category: "ui")
    static let meeting = Logger(subsystem: "com.mywhispers.app", category: "meeting")
}
