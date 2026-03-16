import AppIntents

struct ToggleRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Recording"
    static var description: IntentDescription = "Start or stop voice recording for transcription"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        TranscriptionEngineProvider.shared.engine.toggleRecording()
        return .result()
    }
}

@MainActor
final class TranscriptionEngineProvider {
    static let shared = TranscriptionEngineProvider()
    let engine = TranscriptionEngine()
}
