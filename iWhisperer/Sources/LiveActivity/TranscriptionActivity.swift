import ActivityKit
import Foundation

struct TranscriptionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: Status
        var elapsed: TimeInterval

        enum Status: String, Codable, Hashable {
            case recording
            case transcribing
        }
    }
}
