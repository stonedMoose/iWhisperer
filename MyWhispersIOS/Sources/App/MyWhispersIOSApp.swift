import SwiftUI
import SwiftData

@main
struct MyWhispersIOSApp: App {
    @State private var engine = TranscriptionEngineProvider.shared.engine
    @State private var onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")

    var body: some Scene {
        WindowGroup {
            if onboardingComplete {
                ContentView()
                    .environment(engine)
                    .onAppear {
                        Task { await engine.setup() }
                    }
            } else {
                OnboardingView(isComplete: $onboardingComplete)
                    .environment(engine)
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
                SettingsView()
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
