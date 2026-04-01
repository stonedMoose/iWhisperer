import AppKit
import OSLog
import SwiftUI

@MainActor
final class RecordingIndicator {
    private var window: NSWindow?

    // Tracks the last left-click position globally — used as fallback when AX caret fails
    // (e.g. in Electron apps like VS Code that don't expose caret bounds via AX).
    // Users always click to position their cursor before typing, so this is accurate.
    private static var lastClickPosition: NSPoint?
    private static var clickMonitorInstalled = false

    static func installClickMonitor() {
        guard !clickMonitorInstalled else { return }
        clickMonitorInstalled = true
        // Handler is called on the main thread (monitor installed from main thread)
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            RecordingIndicator.lastClickPosition = NSEvent.mouseLocation
        }
    }

    /// Show the recording indicator near the text cursor.
    /// Returns `false` (and beeps) if no text cursor is found.
    @discardableResult
    func show() -> Bool {
        guard window == nil else { return true }

        let caretPoint: NSPoint
        let axCaret = Self.caretScreenPosition()
        if let lastClick = Self.lastClickPosition {
            // We have a last-click baseline. Only trust AX if it's within 300pt
            // of that click — meaning AX is actually tracking cursor movement.
            // Electron apps (VS Code) return an AX position near the document
            // origin, which is far from the real click location.
            if let caret = axCaret, hypot(caret.x - lastClick.x, caret.y - lastClick.y) < 300 {
                Log.ui.info("Using AX caret (close to last click): x=\(caret.x, privacy: .public) y=\(caret.y, privacy: .public)")
                caretPoint = caret
            } else {
                Log.ui.info("Using last click (AX absent or too far): x=\(lastClick.x, privacy: .public) y=\(lastClick.y, privacy: .public)")
                caretPoint = lastClick
            }
        } else if let caret = axCaret {
            caretPoint = caret
        } else {
            let mouse = NSEvent.mouseLocation
            Log.ui.info("No click history, falling back to mouse: x=\(mouse.x, privacy: .public) y=\(mouse.y, privacy: .public)")
            caretPoint = mouse
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

        let focusedElement = focused as! AXUIElement  // CF bridged type — cast always succeeds per compiler

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
        let boundsAXValue = bounds as! AXValue  // CF bridged type — cast always succeeds per compiler
        guard AXValueGetValue(boundsAXValue, .cgRect, &rect) else { return nil }

        Log.ui.info("AX caret rect: x=\(rect.origin.x, privacy: .public) y=\(rect.origin.y, privacy: .public) w=\(rect.size.width, privacy: .public) h=\(rect.size.height, privacy: .public)")

        // Validate caret is within the focused window (rejects bogus origins like (0,0) from Electron apps)
        var windowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
           let windowRef = windowValue {
            let windowElement = windowRef as! AXUIElement
            var winPosVal: CFTypeRef?
            var winSizeVal: CFTypeRef?
            if AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &winPosVal) == .success,
               AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &winSizeVal) == .success,
               let wp = winPosVal, let ws = winSizeVal {
                var winPos = CGPoint.zero
                var winSize = CGSize.zero
                AXValueGetValue(wp as! AXValue, .cgPoint, &winPos)
                AXValueGetValue(ws as! AXValue, .cgSize, &winSize)
                let winFrame = CGRect(origin: winPos, size: winSize).insetBy(dx: -4, dy: -4)
                if !winFrame.contains(rect.origin) {
                    Log.ui.info("AX caret origin outside window frame — falling back to mouse")
                    return nil
                }
            }
        }

        // AX coordinates: origin at top-left of primary display
        // AppKit coordinates: origin at bottom-left of primary display
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
        guard primaryScreenHeight > 0 else { return nil }
        let flippedY = primaryScreenHeight - rect.origin.y - rect.size.height

        let converted = NSPoint(x: rect.origin.x, y: flippedY)
        // Reject if converted point is off all screens
        guard NSScreen.screens.contains(where: { $0.frame.contains(converted) }) else {
            Log.ui.info("AX caret maps off-screen — falling back to mouse")
            return nil
        }
        return converted
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
