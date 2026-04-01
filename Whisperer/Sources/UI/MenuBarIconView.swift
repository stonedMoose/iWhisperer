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
    var language: WhisperLanguage = .auto { didSet { rebuildImage() } }

    private(set) var image: NSImage

    private var dotVisible = true
    private var pulseTimer: Timer?

    init() {
        self.image = Self.renderIcon(dotColor: nil, language: .auto)
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
        image = Self.renderIcon(dotColor: dotColor, language: language)
    }

    private static func renderIcon(dotColor: NSColor?, language: WhisperLanguage) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Whisperer")?
            .withSymbolConfiguration(config) else { return NSImage(size: size) }
        symbol.isTemplate = true
        let symbolSize = symbol.size
        let sx = (size.width - symbolSize.width) / 2
        let sy = (size.height - symbolSize.height) / 2
        let symbolRect = CGRect(x: sx, y: sy, width: symbolSize.width, height: symbolSize.height)

        // No flag pattern (auto-detect) — use existing template rendering
        guard let flagPattern = language.flagPattern else {
            guard let dotColor else {
                let img = NSImage(size: size, flipped: false) { _ in
                    symbol.draw(in: NSRect(x: sx, y: sy, width: symbolSize.width, height: symbolSize.height))
                    return true
                }
                img.isTemplate = true
                return img
            }
            return renderWithDot(symbol: symbol, symbolRect: symbolRect, dotColor: dotColor, size: size)
        }

        // Flag mode: paint flag through waveform mask using sourceAtop
        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // 1. Draw waveform to establish destination alpha
            symbol.draw(in: NSRect(x: sx, y: sy, width: symbolSize.width, height: symbolSize.height))

            // 2. sourceAtop: subsequent draws only affect pixels where waveform exists
            ctx.setBlendMode(.sourceAtop)
            Self.drawFlagBands(flagPattern, in: symbolRect, ctx: ctx)
            if let overlay = flagPattern.overlay {
                Self.drawFlagOverlay(overlay, in: symbolRect, ctx: ctx)
            }

            // 3. Normal blend for the state dot
            ctx.setBlendMode(.normal)
            if let dotColor {
                let dotSize: CGFloat = 6
                ctx.setFillColor(dotColor.cgColor)
                ctx.fillEllipse(in: CGRect(x: rect.width - dotSize, y: 0, width: dotSize, height: dotSize))
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    /// Template-style rendering with dot (used for auto-detect + active state).
    private static func renderWithDot(symbol: NSImage, symbolRect: CGRect, dotColor: NSColor, size: NSSize) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            symbol.draw(in: NSRect(origin: symbolRect.origin, size: symbolRect.size))
            ctx.setBlendMode(.sourceAtop)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(symbolRect)
            ctx.setBlendMode(.normal)
            let dotSize: CGFloat = 6
            ctx.setFillColor(dotColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: rect.width - dotSize, y: 0, width: dotSize, height: dotSize))
            return true
        }
        img.isTemplate = false
        return img
    }

    private static func drawFlagBands(_ pattern: FlagPattern, in rect: CGRect, ctx: CGContext) {
        let total = pattern.bands.reduce(0) { $0 + $1.weight }
        switch pattern.orientation {
        case .vertical:
            var x = rect.minX
            for band in pattern.bands {
                let w = rect.width * (band.weight / total)
                ctx.setFillColor(band.color.cgColor)
                ctx.fill(CGRect(x: x, y: rect.minY, width: w, height: rect.height))
                x += w
            }
        case .horizontal:
            // bands[0] = visual top; CG y=0 is bottom, so draw top-down from maxY
            var currentY = rect.maxY
            for band in pattern.bands {
                let h = rect.height * (band.weight / total)
                ctx.setFillColor(band.color.cgColor)
                ctx.fill(CGRect(x: rect.minX, y: currentY - h, width: rect.width, height: h))
                currentY -= h
            }
        }
    }

    private static func drawFlagOverlay(_ overlay: FlagPattern.Overlay, in rect: CGRect, ctx: CGContext) {
        switch overlay {
        case .circle(let color, let cx, let cy, let r):
            ctx.setFillColor(color.cgColor)
            let cr = r * min(rect.width, rect.height)
            ctx.fillEllipse(in: CGRect(
                x: rect.minX + cx * rect.width - cr,
                y: rect.minY + cy * rect.height - cr,
                width: cr * 2, height: cr * 2))

        case .cross(let h, let v):
            let thick = rect.width * 0.22
            // White backing for fimbriation (Union Jack style)
            let whiteFactor: CGFloat = 1.6
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: rect.minX, y: rect.midY - thick * whiteFactor / 2,
                            width: rect.width, height: thick * whiteFactor))
            ctx.fill(CGRect(x: rect.midX - thick * whiteFactor / 2, y: rect.minY,
                            width: thick * whiteFactor, height: rect.height))
            // Coloured cross on top
            ctx.setFillColor(h.cgColor)
            ctx.fill(CGRect(x: rect.minX, y: rect.midY - thick/2, width: rect.width, height: thick))
            ctx.setFillColor(v.cgColor)
            ctx.fill(CGRect(x: rect.midX - thick/2, y: rect.minY, width: thick, height: rect.height))

        case .star(let color, let cx, let cy, let r):
            let starR = r * min(rect.width, rect.height)
            let px = rect.minX + cx * rect.width
            let py = rect.minY + cy * rect.height
            ctx.setFillColor(color.cgColor)
            let path = CGMutablePath()
            for i in 0..<5 {
                let outerAngle = CGFloat(i) * 4 * .pi / 5 - .pi / 2
                let innerAngle = outerAngle + 2 * .pi / 5
                let outerPt = CGPoint(x: px + cos(outerAngle) * starR, y: py + sin(outerAngle) * starR)
                let innerPt = CGPoint(x: px + cos(innerAngle) * starR * 0.4, y: py + sin(innerAngle) * starR * 0.4)
                if i == 0 { path.move(to: outerPt) } else { path.addLine(to: outerPt) }
                path.addLine(to: innerPt)
            }
            path.closeSubpath()
            ctx.addPath(path)
            ctx.fillPath()

        case .yinYang(let top, let bottom, let r):
            let yr = r * min(rect.width, rect.height)
            let cxPt = rect.midX
            let cyPt = rect.midY
            // Full circle bottom colour
            ctx.setFillColor(bottom.cgColor)
            ctx.fillEllipse(in: CGRect(x: cxPt - yr, y: cyPt - yr, width: yr*2, height: yr*2))
            // Top half filled with top colour
            ctx.setFillColor(top.cgColor)
            ctx.fillEllipse(in: CGRect(x: cxPt - yr, y: cyPt, width: yr*2, height: yr))
            // Small inner circles for classic look
            ctx.setFillColor(top.cgColor)
            ctx.fillEllipse(in: CGRect(x: cxPt - yr/4, y: cyPt + yr/4, width: yr/2, height: yr/2))
            ctx.setFillColor(bottom.cgColor)
            ctx.fillEllipse(in: CGRect(x: cxPt - yr/4, y: cyPt - yr*3/4, width: yr/2, height: yr/2))
        }
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
    let language: WhisperLanguage  // NEW

    @State private var iconState = MenuBarIconState()

    var body: some View {
        Image(nsImage: iconState.image)
            .onChange(of: isMeetingRecording, initial: true) { _, val in iconState.isMeetingRecording = val }
            .onChange(of: isRecording, initial: true) { _, val in iconState.isRecording = val }
            .onChange(of: isProcessing, initial: true) { _, val in iconState.isProcessing = val }
            .onChange(of: isMeetingProcessing, initial: true) { _, val in iconState.isMeetingProcessing = val }
            .onChange(of: language, initial: true) { _, val in iconState.language = val }
    }
}
