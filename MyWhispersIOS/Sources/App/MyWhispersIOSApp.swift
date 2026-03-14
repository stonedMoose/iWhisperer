import SwiftUI

@main
struct MyWhispersIOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        NavigationStack {
            Text("MyWhispers")
                .navigationTitle("MyWhispers")
        }
    }
}
