import Foundation
import SwiftData

@Model
final class Transcription {
    var text: String
    var language: String
    var model: String
    var duration: TimeInterval
    var createdAt: Date

    init(text: String, language: String, model: String, duration: TimeInterval) {
        self.text = text
        self.language = language
        self.model = model
        self.duration = duration
        self.createdAt = Date()
    }
}
