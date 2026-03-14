import SwiftUI
import SwiftData

@main
struct MyWhispersIOSApp: App {
    @State private var engine = TranscriptionEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engine)
                .onAppear {
                    Task { await engine.setup() }
                }
        }
        .modelContainer(for: Transcription.self)
    }
}

struct ContentView: View {
    @Environment(TranscriptionEngine.self) private var engine
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            RecordingView()
                .tabItem {
                    Label("Record", systemImage: "mic.fill")
                }

            NavigationStack {
                HistoryView()
                    .navigationTitle("History")
            }
            .tabItem {
                Label("History", systemImage: "clock")
            }

            NavigationStack {
                Text("Settings")
                    .navigationTitle("Settings")
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .onAppear {
            engine.setModelContext(modelContext)
        }
    }
}
