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
        case support     = "Support"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general:     "gearshape"
            case .languages:   "globe"
            case .batch:       "waveform"
            case .streaming:   "antenna.radiowaves.left.and.right"
            case .meeting:     "person.3"
            case .permissions: "lock.shield"
            case .support:     "questionmark.circle"
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
        // Observe appLanguage so the entire settings view re-renders when the interface language changes
        let _ = settings.appLanguage
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
                    Label(sectionName(section), systemImage: section.icon)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            detailView
                .navigationTitle(sectionName(selectedSection))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar(removing: .sidebarToggle)
        .background(ToolbarRemover())
        .frame(width: 760, height: 520)
    }

    private func sectionName(_ section: Section) -> String {
        switch section {
        case .general:     L10n.general
        case .languages:   L10n.sectionLanguages
        case .batch:       L10n.sectionTranscription
        case .streaming:   L10n.sectionStreaming
        case .meeting:     L10n.meeting
        case .permissions: L10n.settingsPermissions
        case .support:     L10n.sectionSupport
        }
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
        case .support:     SupportSection()
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
            Section(L10n.settingsStartup) {
                Toggle(L10n.launchAtLogin, isOn: $settings.launchAtLogin)
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
                Picker(L10n.settingsInputDevice, selection: $settings.selectedMicrophoneUID) {
                    Text("System Default").tag("")
                    if !devices.isEmpty {
                        Divider()
                        ForEach(devices) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                }
            } header: {
                Text(L10n.settingsMicrophone)
            } footer: {
                Text("Overrides the system default microphone for all recording modes.")
            }

            Section {
                Picker(L10n.language, selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            } header: {
                Text(L10n.settingsInterfaceLanguage)
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
                LabeledContent(L10n.settingsCycleLanguages) {
                    KeyboardShortcuts.Recorder(for: .cycleLanguage)
                }
            } header: {
                Text(L10n.settingsShortcut)
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
                Text(L10n.preferredLanguages)
            } footer: {
                Text(L10n.preferredLanguagesCaption)
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
                LabeledContent(L10n.settingsHoldToRecord) {
                    KeyboardShortcuts.Recorder(for: .holdToRecord)
                }
            } header: {
                Text(L10n.settingsShortcut)
            } footer: {
                Text("Hold the key to record; release to transcribe and insert text at the cursor.")
            }

            Section {
                Toggle(L10n.settingsShowWordsAsYouSpeak, isOn: $settings.streamingMode)
            } header: {
                Text(L10n.settingsLivePreview)
            } footer: {
                Text("Words appear in real time while you hold the key. Configure the streaming model in the Streaming section.")
            }

            Section {
                Picker(L10n.model, selection: $settings.selectedModel) {
                    ForEach(WhisperModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .onChange(of: settings.selectedModel) { _, _ in
                    NotificationCenter.default.post(name: .modelChanged, object: nil)
                }
            } header: {
                Text(L10n.model)
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
                Toggle(L10n.settingsEnableLivePreview, isOn: $settings.streamingMode)
            } header: {
                Text(L10n.settingsLivePreview)
            } footer: {
                Text("Words appear in real time using a sliding window while you speak, then are confirmed when you release the key.")
            }

            Section {
                Picker(L10n.model, selection: Binding(
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
                    LabeledContent(L10n.settingsStatus) {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(L10n.settingsLoadingModel)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(L10n.settingsStreamingModel)
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
                LabeledContent(L10n.settingsToggleRecording) {
                    KeyboardShortcuts.Recorder(for: .meetingRecord)
                }
            } header: {
                Text(L10n.settingsShortcut)
            } footer: {
                Text("Press once to start and again to stop. Transcription with speaker identification runs automatically.")
            }

            Section {
                LabeledContent(L10n.settingsSaveTo) {
                    HStack(spacing: 8) {
                        Text(settings.transcriptDirectory.lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(L10n.choose) {
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
                Text(L10n.transcriptLocation)
            } footer: {
                Text("Each meeting is saved as a Markdown file named with the date and time.")
            }

            Section {
                Toggle(L10n.settingsRefineWithAI, isOn: $settings.refinementEnabled)

                Picker(L10n.provider, selection: $settings.refinementProvider) {
                    ForEach(LLMProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: settings.refinementProvider) { _, newValue in
                    settings.refinementModel = newValue.defaultModel
                }

                if settings.refinementProvider.requiresAPIKey {
                    SecureField(L10n.apiKey, text: $settings.refinementAPIKey)
                }

                TextField(L10n.settingsModelID, text: $settings.refinementModel)

                LabeledContent(L10n.prompt) {
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
                    Button(L10n.settingsResetToDefault) {
                        settings.refinementPrompt = SettingsStore.defaultRefinementPrompt
                    }
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text(L10n.aiRefinement)
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
                    title: L10n.settingsMicrophone,
                    description: "Required to capture audio during recording.",
                    isGranted: appState.micPermissionGranted,
                    action: { appState.openMicrophoneSettings() }
                )

                PermissionCard(
                    icon: "accessibility",
                    title: L10n.settingsAccessibility,
                    description: "Required to insert transcribed text at the cursor position.",
                    isGranted: appState.accessibilityPermissionGranted,
                    action: { appState.openAccessibilitySettings() }
                )
            } header: {
                Text(L10n.settingsRequiredPermissions)
            } footer: {
                Text("Both permissions are needed for full functionality. After granting Accessibility, restart the app.")
            }

            Section {
                Button(L10n.settingsOpenSetupGuide) {
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

// MARK: - Support

private struct SupportSection: View {
    @State private var bugDescription = ""

    var body: some View {
        Form {
            Section {
                LabeledContent(L10n.settingsBugDescription) {
                    TextEditor(text: $bugDescription)
                        .font(.body)
                        .frame(minHeight: 90)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.08))
                        )
                }

                HStack {
                    Spacer()
                    Button(L10n.settingsSendBugReport) {
                        sendBugReport()
                    }
                    .disabled(bugDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text(L10n.settingsBugReport)
            } footer: {
                Text("Opens Mail with a pre-filled report to moose@lumpy.me including your description and the last 5 minutes of app logs.")
            }
        }
        .formStyle(.grouped)
    }

    private func sendBugReport() {
        let logs = collectRecentLogs()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let body = """
        Bug Description:
        \(bugDescription.trimmingCharacters(in: .whitespacesAndNewlines))

        --- App Logs (last 5 min) ---
        \(logs)

        --- System Info ---
        MacWhisperer \(version)
        macOS \(os)
        """
        let subject = "MacWhisperer Bug Report"
        guard let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "mailto:moose@lumpy.me?subject=\(encodedSubject)&body=\(encodedBody)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func collectRecentLogs() -> String {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else {
            return "(unable to access logs)"
        }
        let since = Date().addingTimeInterval(-300)
        let position = store.position(date: since)
        guard let entries = try? store.getEntries(at: position) else {
            return "(unable to retrieve logs)"
        }
        let lines = entries
            .compactMap { $0 as? OSLogEntryLog }
            .suffix(150)
            .map { "[\($0.category)] \($0.composedMessage)" }
        return lines.isEmpty ? "(no recent logs)" : lines.joined(separator: "\n")
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
