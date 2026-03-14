import SwiftUI

struct OnboardingView: View {
    @Environment(TranscriptionEngine.self) private var engine
    @Binding var isComplete: Bool

    @State private var step = 0

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            switch step {
            case 0:
                welcomeStep
            case 1:
                micPermissionStep
            case 2:
                modelDownloadStep
            default:
                EmptyView()
            }

            Spacer()
        }
        .padding()
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
            Text("MyWhispers")
                .font(.largeTitle.bold())
            Text("Voice to text, powered by local AI.\nNo internet required.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Get Started") { step = 1 }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private var micPermissionStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.orange)
            Text("Microphone Access")
                .font(.title2.bold())
            Text("MyWhispers needs microphone access to record your voice.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Allow Microphone") {
                Task {
                    await engine.checkMicPermission()
                    step = 2
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var modelDownloadStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
            Text("Download Model")
                .font(.title2.bold())
            Text("Download the \(engine.selectedModel.displayName) speech recognition model.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Picker("Model", selection: Bindable(engine).selectedModel) {
                ForEach(WhisperModel.allCases) { model in
                    Text(model.displayName).tag(model)
                }
            }
            .pickerStyle(.segmented)

            if engine.isDownloadingModel {
                ProgressView(value: engine.downloadProgress) {
                    Text("Downloading... \(Int(engine.downloadProgress * 100))%")
                }
                .padding(.horizontal)
            } else if engine.isModelLoaded {
                Button("Done") {
                    UserDefaults.standard.set(true, forKey: "onboardingComplete")
                    isComplete = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button("Download & Continue") {
                    Task { await engine.loadModel() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
}
