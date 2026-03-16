import AVFoundation
import SwiftUI

struct SetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text(L10n.setupWelcomeTitle)
                    .font(.title2.bold())

                Text(L10n.setupWelcomeSubtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Divider()

            // Permission 1: Microphone
            PermissionRow(
                icon: "mic.fill",
                title: L10n.setupMicrophoneTitle,
                description: L10n.setupMicrophoneDescription,
                isGranted: appState.micPermissionGranted,
                actionLabel: L10n.setupGrant,
                action: {
                    appState.openMicrophoneSettings()
                }
            )

            // Permission 2: Accessibility
            PermissionRow(
                icon: "accessibility",
                title: L10n.setupAccessibilityTitle,
                description: L10n.setupAccessibilityDescription,
                isGranted: appState.accessibilityPermissionGranted,
                actionLabel: L10n.setupGrant,
                action: {
                    appState.openAccessibilitySettings()
                }
            )

            if appState.accessibilityPermissionGranted && appState.micPermissionGranted {
                Label(L10n.setupAllGranted, systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                Text(L10n.setupRestartNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            HStack {
                Button(L10n.setupRecheck) {
                    appState.recheckPermissions()
                }

                Spacer()

                if appState.accessibilityPermissionGranted && appState.micPermissionGranted {
                    Button(L10n.setupGetStarted) {
                        settings.hasCompletedSetup = true
                        onDismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(L10n.setupSkip) {
                        settings.hasCompletedSetup = true
                        onDismiss()
                    }
                }
            }
        }
        .padding(32)
        .frame(width: 480, height: 460)
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let actionLabel: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(isGranted ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.headline)

                    if isGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isGranted {
                Button(actionLabel) {
                    action()
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isGranted ? Color.green.opacity(0.08) : Color.secondary.opacity(0.06))
        )
    }
}
