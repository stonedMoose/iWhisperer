import SwiftUI

struct RecordingView: View {
    @Environment(TranscriptionEngine.self) private var engine

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            statusView
            recordButton
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var statusView: some View {
        switch engine.state {
        case .idle:
            VStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Tap to record")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

        case .recording(let elapsed):
            VStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
                Text(formatElapsed(elapsed))
                    .font(.system(.title, design: .monospaced))
                    .foregroundStyle(.red)
            }

        case .transcribing:
            VStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Transcribing...")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

        case .done(let text):
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text(text)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .padding(.horizontal)
                if engine.autoCopy {
                    Text("Copied to clipboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .error(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var recordButton: some View {
        Button {
            engine.toggleRecording()
        } label: {
            Circle()
                .fill(buttonColor)
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: buttonIcon)
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                }
        }
        .disabled(engine.state == .transcribing)
    }

    private var buttonColor: Color {
        switch engine.state {
        case .recording: .red
        case .transcribing: .gray
        default: .blue
        }
    }

    private var buttonIcon: String {
        switch engine.state {
        case .recording: "stop.fill"
        case .transcribing: "hourglass"
        default: "mic.fill"
        }
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", m, s, ms)
    }
}
