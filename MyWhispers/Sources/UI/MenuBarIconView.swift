import AppKit
import SwiftUI

/// Manages the pulsing dot state for the menu bar icon.
/// The waveform is always a template image (separate layer), so it stays system-tinted.
/// The dot is rendered as its own non-template NSImage overlay to preserve its color.
@Observable
@MainActor
final class MenuBarIconState {
    var isMeetingRecording = false { didSet { update() } }
    var isRecording = false { didSet { update() } }
    var isProcessing = false { didSet { update() } }
    var isMeetingProcessing = false { didSet { update() } }

    private(set) var dotImage: NSImage?

    private var dotVisible = true
    private var pulseTimer: Timer?

    private var shouldPulse: Bool {
        isMeetingRecording || isProcessing || isMeetingProcessing
    }

    private func update() {
        if shouldPulse {
            startPulse()
        } else {
            stopPulse()
        }
        rebuildDot()
    }

    private func rebuildDot() {
        let dotColor: NSColor?
        if isMeetingRecording {
            dotColor = dotVisible ? .red : .red.withAlphaComponent(0.3)
        } else if isRecording {
            dotColor = .red
        } else if isProcessing || isMeetingProcessing {
            dotColor = dotVisible ? .orange : .orange.withAlphaComponent(0.3)
        } else {
            dotColor = nil
        }

        guard let dotColor else {
            dotImage = nil
            return
        }

        let dotSize: CGFloat = 6
        let img = NSImage(size: NSSize(width: dotSize, height: dotSize), flipped: false) { rect in
            dotColor.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        img.isTemplate = false
        dotImage = img
    }

    private func startPulse() {
        guard pulseTimer == nil else { return }
        dotVisible = true
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.dotVisible.toggle()
                self.rebuildDot()
            }
        }
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        dotVisible = true
    }

    deinit {
        MainActor.assumeIsolated {
            pulseTimer?.invalidate()
        }
    }
}

struct MenuBarIconView: View {
    let isMeetingRecording: Bool
    let isRecording: Bool
    let isProcessing: Bool
    let isMeetingProcessing: Bool

    @State private var iconState = MenuBarIconState()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Waveform — always template, system handles tinting
            Image(systemName: "waveform")

            // Colored dot overlay
            if let dotImage = iconState.dotImage {
                Image(nsImage: dotImage)
                    .offset(x: 2, y: 2)
            }
        }
        .onChange(of: isMeetingRecording) { _, val in iconState.isMeetingRecording = val }
        .onChange(of: isRecording) { _, val in iconState.isRecording = val }
        .onChange(of: isProcessing) { _, val in iconState.isProcessing = val }
        .onChange(of: isMeetingProcessing) { _, val in iconState.isMeetingProcessing = val }
    }
}
