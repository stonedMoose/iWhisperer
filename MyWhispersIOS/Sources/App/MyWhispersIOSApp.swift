import SwiftUI
import SwiftData

@main
struct MyWhispersIOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Transcription.self)
    }
}

struct ContentView: View {
    var body: some View {
        NavigationStack {
            HistoryView()
                .navigationTitle("MyWhispers")
        }
    }
}
