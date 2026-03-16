import ActivityKit
import SwiftUI
import WidgetKit

struct TranscriptionActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TranscriptionActivityAttributes.self) { context in
            // Lock Screen view
            HStack {
                Image(systemName: context.state.status == .recording ? "mic.fill" : "waveform")
                    .foregroundStyle(context.state.status == .recording ? .red : .blue)

                VStack(alignment: .leading) {
                    Text(context.state.status == .recording ? "Recording..." : "Transcribing...")
                        .font(.headline)
                    Text(formatElapsed(context.state.elapsed))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.status == .recording ? "mic.fill" : "waveform")
                        .foregroundStyle(context.state.status == .recording ? .red : .blue)
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack {
                        Text(context.state.status == .recording ? "Recording" : "Transcribing")
                            .font(.headline)
                        Text(formatElapsed(context.state.elapsed))
                            .font(.system(.body, design: .monospaced))
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.status == .recording ? "mic.fill" : "waveform")
                    .foregroundStyle(context.state.status == .recording ? .red : .blue)
            } compactTrailing: {
                Text(formatElapsed(context.state.elapsed))
                    .font(.system(.caption, design: .monospaced))
            } minimal: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
