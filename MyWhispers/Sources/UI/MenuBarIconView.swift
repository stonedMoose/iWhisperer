import AppKit
import SwiftUI

final class StatusBarIconNSView: NSView {
    var isMeetingRecording = false { didSet { updateDot() } }
    var isRecording = false { didSet { updateDot() } }
    var isProcessing = false { didSet { updateDot() } }
    var isMeetingProcessing = false { didSet { updateDot() } }

    private var dotVisible = true
    private var pulseTimer: Timer?

    override var intrinsicContentSize: NSSize {
        NSSize(width: 18, height: 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        guard let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "MyWhispers")?
            .withSymbolConfiguration(config) else { return }

        image.isTemplate = true
        let imageSize = image.size
        let x = (bounds.width - imageSize.width) / 2
        let y = (bounds.height - imageSize.height) / 2
        image.draw(in: NSRect(x: x, y: y, width: imageSize.width, height: imageSize.height))

        let dotColor: NSColor?
        if isMeetingRecording {
            dotColor = dotVisible ? .red : .red.withAlphaComponent(0.3)
        } else if isRecording {
            dotColor = .red
        } else if isProcessing || isMeetingProcessing {
            dotColor = .orange
        } else {
            dotColor = nil
        }

        if let color = dotColor {
            let dotSize: CGFloat = 7
            let dotRect = NSRect(
                x: bounds.width - dotSize,
                y: 0,
                width: dotSize,
                height: dotSize
            )
            color.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }
    }

    private func updateDot() {
        if isMeetingRecording {
            startPulse()
        } else {
            stopPulse()
        }
        needsDisplay = true
    }

    private func startPulse() {
        guard pulseTimer == nil else { return }
        dotVisible = true
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.dotVisible.toggle()
            self.needsDisplay = true
        }
    }

    deinit {
        pulseTimer?.invalidate()
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        dotVisible = true
    }
}

struct MenuBarIconView: NSViewRepresentable {
    let isMeetingRecording: Bool
    let isRecording: Bool
    let isProcessing: Bool
    let isMeetingProcessing: Bool

    func makeNSView(context: Context) -> StatusBarIconNSView {
        let view = StatusBarIconNSView()
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: StatusBarIconNSView, context: Context) {
        nsView.isMeetingRecording = isMeetingRecording
        nsView.isRecording = isRecording
        nsView.isProcessing = isProcessing
        nsView.isMeetingProcessing = isMeetingProcessing
    }
}
