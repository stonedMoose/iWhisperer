import AppIntents

struct MyWhispersShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleRecordingIntent(),
            phrases: [
                "Transcribe with \(.applicationName)",
                "Record with \(.applicationName)",
                "Dictate with \(.applicationName)"
            ],
            shortTitle: "Transcribe",
            systemImageName: "mic.fill"
        )
    }
}
