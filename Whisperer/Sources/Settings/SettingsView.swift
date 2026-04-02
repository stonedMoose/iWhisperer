import OSLog
import ServiceManagement
import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let holdToRecord = Self("holdToRecord")
    static let meetingRecord = Self("meetingRecord")
    static let cycleLanguage = Self("cycleLanguage")
}

// MARK: - Root

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppState.self) private var appState

    private enum Section: String, CaseIterable, Identifiable {
        case general     = "General"
        case languages   = "Languages"
        case batch       = "Transcription"
        case streaming   = "Streaming"
        case meeting     = "Meeting"
        case permissions = "Permissions"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general:     "gearshape"
            case .languages:   "globe"
            case .batch:       "waveform"
            case .streaming:   "antenna.radiowaves.left.and.right"
            case .meeting:     "person.3"
            case .permissions: "lock.shield"
            }
        }
    }

    @State private var selectedSection: Section = .general
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty || build == version ? version : "\(version) (\(build))"
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    if let icon = NSImage(named: "AppIcon") {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 56, height: 56)
                    }
                    VStack(spacing: 1) {
                        Text("MacWhisperer")
                            .font(.headline)
                        Text("Version \(appVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 12)

                Divider()

                List(Section.allCases, selection: $selectedSection) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            detailView
                .navigationTitle(selectedSection.rawValue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar(removing: .sidebarToggle)
        .background(ToolbarRemover())
        .frame(width: 760, height: 520)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .general:     GeneralSection()
        case .languages:   LanguagesSection()
        case .batch:       BatchSection()
        case .streaming:   StreamingSection()
        case .meeting:     MeetingSection()
        case .permissions: PermissionsSection()
        }
    }
}

// MARK: - General

private struct GeneralSection: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        let devices = AudioDeviceManager.listInputDevices()
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            settings.launchAtLogin = !newValue
                            Log.general.error("Failed to update login item: \(error)")
                        }
                    }
            }

            Section {
                Picker("Input device", selection: $settings.selectedMicrophoneUID) {
                    Text("System Default").tag("")
                    if !devices.isEmpty {
                        Divider()
                        ForEach(devices) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                }
            } header: {
                Text("Microphone")
            } footer: {
                Text("Overrides the system default microphone for all recording modes.")
            }

            Section {
                Picker("Language", selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .onChange(of: settings.appLanguage) { _, newValue in
                    L10n.current = newValue
                }
            } header: {
                Text("Interface Language")
            } footer: {
                Text("Changes the language of all menus and labels in the app.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Languages

private struct LanguagesSection: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Form {
            Section {
                LabeledContent("Cycle preferred languages") {
                    KeyboardShortcuts.Recorder(for: .cycleLanguage)
                }
            } header: {
                Text("Shortcut")
            } footer: {
                Text("Rotates through your preferred languages in order. Auto-detect is prepended when fewer than two languages are selected.")
            }

            Section {
                ForEach(WhisperLanguage.allCases.filter { $0 != .auto }) { language in
                    Toggle(language.displayName, isOn: Binding(
                        get: { settings.isPreferredLanguage(language) },
                        set: { _ in settings.togglePreferredLanguage(language) }
                    ))
                }
            } header: {
                Text("Preferred Languages")
            } footer: {
                Text("Selected languages appear in the menu bar quick-switch and are cycled by the keyboard shortcut.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Batch

private struct BatchSection: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                LabeledContent("Hold to record") {
                    KeyboardShortcuts.Recorder(for: .holdToRecord)
                }
            } header: {
                Text("Shortcut")
            } footer: {
                Text("Hold the key to record; release to transcribe and insert text at the cursor.")
            }

            Section {
                Toggle("Show words as you speak", isOn: $settings.streamingMode)
            } header: {
                Text("Live Preview")
            } footer: {
                Text("Words appear in real time while you hold the key. Configure the streaming model in the Streaming section.")
            }

            Section {
                Picker("Model", selection: $settings.selectedModel) {
                    ForEach(WhisperModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .onChange(of: settings.selectedModel) { _, _ in
                    NotificationCenter.default.post(name: .modelChanged, object: nil)
                }
            } header: {
                Text("Model")
            } footer: {
                Text("Transcription runs after you release the key. Larger models produce more accurate results at the cost of processing time.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Streaming

private struct StreamingSection: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Enable live preview", isOn: $settings.streamingMode)
            } header: {
                Text("Live Preview")
            } footer: {
                Text("Words appear in real time using a sliding window while you speak, then are confirmed when you release the key.")
            }

            Section {
                Picker("Model", selection: Binding(
                    get: { settings.streamingModel ?? settings.selectedModel },
                    set: { newModel in
                        settings.streamingModel = newModel == settings.selectedModel ? nil : newModel
                        NotificationCenter.default.post(name: .streamingModelChanged, object: nil)
                    }
                )) {
                    ForEach(WhisperModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }

                if settings.streamingMode && !appState.isStreamingModelLoaded {
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Loading model…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Streaming Model")
            } footer: {
                streamingModelFooter
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var streamingModelFooter: some View {
        if settings.streamingModel == nil {
            Text("Using the same model as batch. Select a smaller model (Tiny or Base) to reduce first-word latency to under one second.")
        } else {
            Text("A dedicated streaming model lets you preview quickly while the batch model delivers accuracy when you finish speaking.")
        }
    }
}

// MARK: - Meeting

private struct MeetingSection: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                LabeledContent("Toggle recording") {
                    KeyboardShortcuts.Recorder(for: .meetingRecord)
                }
            } header: {
                Text("Shortcut")
            } footer: {
                Text("Press once to start and again to stop. Transcription with speaker identification runs automatically.")
            }

            Section {
                LabeledContent("Save to") {
                    HStack(spacing: 8) {
                        Text(settings.transcriptDirectory.lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.directoryURL = settings.transcriptDirectory
                            if panel.runModal() == .OK, let url = panel.url {
                                settings.transcriptDirectory = url
                            }
                        }
                        .controlSize(.small)
                    }
                }
            } header: {
                Text("Transcript Location")
            } footer: {
                Text("Each meeting is saved as a Markdown file named with the date and time.")
            }

            Section {
                Toggle("Refine with AI after transcription", isOn: $settings.refinementEnabled)

                Picker("Provider", selection: $settings.refinementProvider) {
                    ForEach(LLMProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: settings.refinementProvider) { _, newValue in
                    settings.refinementModel = newValue.defaultModel
                }

                if settings.refinementProvider.requiresAPIKey {
                    SecureField("API Key", text: $settings.refinementAPIKey)
                }

                TextField("Model ID", text: $settings.refinementModel)

                LabeledContent("Prompt") {
                    TextEditor(text: $settings.refinementPrompt)
                        .font(.body)
                        .frame(minHeight: 110)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.08))
                        )
                }

                HStack {
                    Spacer()
                    Button("Reset to default") {
                        settings.refinementPrompt = SettingsStore.defaultRefinementPrompt
                    }
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("AI Refinement")
            } footer: {
                Text("After speaker diarization, an LLM identifies speakers by name and fixes cross-speaker attribution errors.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Permissions

private struct PermissionsSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section {
                PermissionCard(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Required to capture audio during recording.",
                    isGranted: appState.micPermissionGranted,
                    action: { appState.openMicrophoneSettings() }
                )

                PermissionCard(
                    icon: "accessibility",
                    title: "Accessibility",
                    description: "Required to insert transcribed text at the cursor position.",
                    isGranted: appState.accessibilityPermissionGranted,
                    action: { appState.openAccessibilitySettings() }
                )
            } header: {
                Text("Required Permissions")
            } footer: {
                Text("Both permissions are needed for full functionality. After granting Accessibility, restart the app.")
            }

            Section {
                Button("Open setup guide…") {
                    openWindow(id: "setup")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Card-style permission row matching the SetupView design language.
private struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(isGranted ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                    if isGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isGranted {
                Button("Grant…", action: action)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isGranted ? Color.green.opacity(0.08) : Color.secondary.opacity(0.06))
        )
    }
}

// MARK: - Toolbar remover

private struct ToolbarRemover: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.toolbar = nil
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Notification names

extension Notification.Name {
    static let modelChanged = Notification.Name("modelChanged")
    static let streamingModelChanged = Notification.Name("streamingModelChanged")
}
