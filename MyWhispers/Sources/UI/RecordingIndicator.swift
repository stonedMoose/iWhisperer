import AppKit
import SwiftUI

@MainActor
final class RecordingIndicator {
    private var window: NSWindow?

    func show() {
        guard window == nil else { return }

        let size: CGFloat = 20
        let mouseLocation = NSEvent.mouseLocation

        let panel = NSPanel(
            contentRect: NSRect(
                x: mouseLocation.x + 16,
                y: mouseLocation.y - size - 8,
                width: size,
                height: size
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(rootView: RecordingDot())
        panel.contentView = hostingView
        panel.orderFrontRegardless()

        window = panel
    }

    func showProcessing() {
        guard let panel = window else { return }
        let hostingView = NSHostingView(rootView: ProcessingDot())
        panel.contentView = hostingView
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

private struct RecordingDot: View {
    @State private var opacity: Double = 1.0

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 16, height: 16)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    opacity = 0.4
                }
            }
    }
}

private struct ProcessingDot: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(.orange, lineWidth: 2)
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
