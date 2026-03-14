import AppKit
import OSLog
import SwiftUI

@MainActor
final class RecordingIndicator {
    private var window: NSWindow?

    /// Show the recording indicator near the text cursor.
    /// Returns `false` (and beeps) if no text cursor is found.
    @discardableResult
    func show() -> Bool {
        guard window == nil else { return true }

        let caretPoint: NSPoint
        if let caret = Self.caretScreenPosition(), (caret.x != 0 || caret.y != 0) {
            caretPoint = caret
        } else {
            // Fallback to mouse cursor when caret position is unavailable or (0,0)
            let mouseLocation = NSEvent.mouseLocation
            Log.ui.info("Caret unavailable, falling back to mouse: x=\(mouseLocation.x, privacy: .public) y=\(mouseLocation.y, privacy: .public)")
            caretPoint = mouseLocation
        }

        let width: CGFloat = 48
        let height: CGFloat = 28

        let panel = NSPanel(
            contentRect: NSRect(
                x: caretPoint.x + 4,
                y: caretPoint.y - height - 4,
                width: width,
                height: height
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(rootView: RecordingWave())
        panel.contentView = hostingView
        panel.orderFrontRegardless()

        window = panel
        return true
    }

    func showProcessing() {
        guard let panel = window else { return }
        panel.setContentSize(NSSize(width: 28, height: 28))
        let hostingView = NSHostingView(rootView: ProcessingDot())
        panel.contentView = hostingView
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }

    /// Query the focused app's text caret position via Accessibility API.
    /// Returns the caret origin in AppKit screen coordinates (bottom-left origin), or nil.
    private static func caretScreenPosition() -> NSPoint? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focused = focusedValue else { return nil }

        guard let focusedElement = focused as? AXUIElement else { return nil }

        // Get the selected text range (cursor position)
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let range = rangeValue else { return nil }

        // Get the screen bounds for that range
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(focusedElement, kAXBoundsForRangeParameterizedAttribute as CFString, range, &boundsValue) == .success,
              let bounds = boundsValue else { return nil }

        // Extract CGRect from the AXValue
        var rect = CGRect.zero
        guard let boundsAXValue = bounds as? AXValue,
              AXValueGetValue(boundsAXValue, .cgRect, &rect) else { return nil }

        // AX coordinates: origin at top-left of primary display
        // AppKit coordinates: origin at bottom-left of primary display
        guard let mainScreen = NSScreen.main else { return nil }
        let flippedY = mainScreen.frame.height - rect.origin.y - rect.size.height

        return NSPoint(x: rect.origin.x, y: flippedY)
    }
}

private struct RecordingWave: View {
    private let barCount = 5
    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 3
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 20

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveBar(
                    minHeight: minHeight,
                    maxHeight: maxHeight,
                    barWidth: barWidth,
                    delay: Double(index) * 0.12
                )
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.7))
        )
    }
}

private struct WaveBar: View {
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let barWidth: CGFloat
    let delay: Double

    @State private var animating = false

    var body: some View {
        RoundedRectangle(cornerRadius: barWidth / 2)
            .fill(
                LinearGradient(
                    colors: [.red, .orange],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: barWidth, height: animating ? maxHeight : minHeight)
            .animation(
                .easeInOut(duration: 0.45)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: animating
            )
            .onAppear { animating = true }
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
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black.opacity(0.7))
            )
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
