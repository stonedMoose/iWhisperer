import SwiftUI

struct SettingsView: View {
    @Environment(TranscriptionEngine.self) private var engine

    var body: some View {
        @Bindable var engine = engine

        Form {
            Section("Whisper Model") {
                Picker("Model", selection: $engine.selectedModel) {
                    ForEach(WhisperModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .onChange(of: engine.selectedModel) {
                    Task { await engine.loadModel() }
                }

                if engine.isDownloadingModel {
                    ProgressView(value: engine.downloadProgress) {
                        Text("Downloading...")
                    }
                }
            }

            Section("Language") {
                Picker("Language", selection: $engine.selectedLanguage) {
                    ForEach(WhisperLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            }

            Section("Behavior") {
                Toggle("Auto-copy to clipboard", isOn: $engine.autoCopy)
            }

            Section("Storage") {
                ForEach(WhisperModel.allCases) { model in
                    ModelStorageRow(model: model)
                }
            }
        }
        .navigationTitle("Settings")
    }
}

struct ModelStorageRow: View {
    let model: WhisperModel
    @State private var isDownloaded = false
    @State private var fileSize: String = ""

    var body: some View {
        HStack {
            Text(model.displayName)
            Spacer()
            if isDownloaded {
                Text(fileSize)
                    .foregroundStyle(.secondary)
                Button("Delete", role: .destructive) {
                    Task {
                        try? await ModelManager.shared.deleteModel(model)
                        await checkStatus()
                    }
                }
                .buttonStyle(.borderless)
            } else {
                Text("Not downloaded")
                    .foregroundStyle(.secondary)
            }
        }
        .task { await checkStatus() }
    }

    private func checkStatus() async {
        isDownloaded = await ModelManager.shared.isModelDownloaded(model)
        if let size = await ModelManager.shared.modelFileSize(model) {
            fileSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
    }
}
