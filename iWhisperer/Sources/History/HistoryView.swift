import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \Transcription.createdAt, order: .reverse)
    private var transcriptions: [Transcription]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            if transcriptions.isEmpty {
                ContentUnavailableView(
                    "No Transcriptions",
                    systemImage: "waveform",
                    description: Text("Press the Action Button to start dictating")
                )
            } else {
                ForEach(transcriptions) { transcription in
                    TranscriptionRow(transcription: transcription)
                }
                .onDelete(perform: delete)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(transcriptions[index])
        }
    }
}

struct TranscriptionRow: View {
    let transcription: Transcription

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(transcription.text)
                .lineLimit(2)
                .font(.body)

            HStack {
                Text(transcription.createdAt, style: .relative)
                Text("\u{00B7}")
                Text(formatDuration(transcription.duration))
                Text("\u{00B7}")
                Text(transcription.language)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = transcription.text
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m \(s % 60)s"
    }
}
