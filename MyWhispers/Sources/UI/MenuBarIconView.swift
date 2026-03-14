import AppKit
import SwiftUI

/// Manages the menu bar icon with an optional pulsing recording/processing dot.
/// Renders a single composited NSImage: template waveform when idle,
/// or a properly tinted waveform + colored dot when active.
@Observable
@MainActor
final class MenuBarIconState {
    var isMeetingRecording = false { didSet { update() } }
    var isRecording = false { didSet { update() } }
    var isProcessing = false { didSet { update() } }
    var isMeetingProcessing = false { didSet { update() } }

    private(set) var image: NSImage

    private var dotVisible = true
    private var pulseTimer: Timer?

    init() {
        self.image = Self.renderIcon(dotColor: nil)
    }

    private var shouldPulse: Bool {
        isMeetingRecording || isProcessing || isMeetingProcessing
    }

    private func update() {
        if shouldPulse {
            startPulse()
        } else {
            stopPulse()
        }
        rebuildImage()
    }

    private func rebuildImage() {
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
        image = Self.renderIcon(dotColor: dotColor)
    }

    private static func renderIcon(dotColor: NSColor?) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: "MyWhispers")?
            .withSymbolConfiguration(config) else {
            return NSImage(size: size)
        }
        symbol.isTemplate = true
        let symbolSize = symbol.size

        guard let dotColor else {
            // No dot — return as template so system handles tinting
            let img = NSImage(size: size, flipped: false) { rect in
                let x = (rect.width - symbolSize.width) / 2
                let y = (rect.height - symbolSize.height) / 2
                symbol.draw(in: NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height))
                return true
            }
            img.isTemplate = true
            return img
        }

        // Composite: tinted waveform + colored dot.
        // Can't use isTemplate=true (dot needs its real color), so we tint
        // the waveform via Core Graphics sourceAtop compositing.
        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // Draw waveform (template renders as black alpha mask)
            let x = (rect.width - symbolSize.width) / 2
            let y = (rect.height - symbolSize.height) / 2
            let symbolRect = NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height)
            symbol.draw(in: symbolRect)

            // Tint waveform pixels to menu bar foreground color (white)
            ctx.setBlendMode(.sourceAtop)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(symbolRect)

            // Draw dot with normal blending
            ctx.setBlendMode(.normal)
            let dotSize: CGFloat = 6
            let dotRect = CGRect(
                x: rect.width - dotSize,
                y: 0,
                width: dotSize,
                height: dotSize
            )
            ctx.setFillColor(dotColor.cgColor)
            ctx.fillEllipse(in: dotRect)

            return true
        }
        img.isTemplate = false
        return img
    }

    private func startPulse() {
        guard pulseTimer == nil else { return }
        dotVisible = true
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.dotVisible.toggle()
                self.rebuildImage()
            }
        }
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        dotVisible = true
    }

}

struct MenuBarIconView: View {
    let isMeetingRecording: Bool
    let isRecording: Bool
    let isProcessing: Bool
    let isMeetingProcessing: Bool

    @State private var iconState = MenuBarIconState()

    var body: some View {
        Image(nsImage: iconState.image)
            .onChange(of: isMeetingRecording, initial: true) { _, val in iconState.isMeetingRecording = val }
            .onChange(of: isRecording, initial: true) { _, val in iconState.isRecording = val }
            .onChange(of: isProcessing, initial: true) { _, val in iconState.isProcessing = val }
            .onChange(of: isMeetingProcessing, initial: true) { _, val in iconState.isMeetingProcessing = val }
    }
}
