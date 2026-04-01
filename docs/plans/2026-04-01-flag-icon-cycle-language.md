# Flag Icon + Language Cycle Shortcut Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Show the active language as a simplified flag rendered through the menu bar waveform icon, and add a configurable global hotkey to cycle through preferred languages.

**Architecture:** `FlagPattern` data structs live in `WhisperModels.swift`. `MenuBarIconState.renderIcon` uses Core Graphics `sourceAtop` blend mode to paint flag bands/shapes through the waveform alpha mask. The cycle shortcut follows the existing `KeyboardShortcuts` pattern already used for `holdToRecord`.

**Tech Stack:** Swift 5.9, AppKit/Core Graphics, `KeyboardShortcuts` SPM package (already installed), `@Observable`

---

## Task 1: Add `FlagPattern` struct and `flagPattern` to `WhisperLanguage`

**Files:**
- Modify: `Whisperer/Sources/Whisper/WhisperModels.swift`

No tests exist in this project. Manual verification: build succeeds, `WhisperLanguage.french.flagPattern` is non-nil in LLDB or via print.

### Step 1: Add `NSColor` convenience initialiser (RGB 0–255 ints)

At the top of `WhisperModels.swift`, above the `WhisperModel` enum, add:

```swift
import AppKit

private extension NSColor {
    /// Convenience init with 0–255 integer components (sRGB).
    convenience init(r: Int, g: Int, b: Int) {
        self.init(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
    }
}
```

### Step 2: Add `FlagPattern` struct

After the `NSColor` extension, before `WhisperModel`, add:

```swift
struct FlagPattern {
    struct Band {
        let color: NSColor
        let weight: CGFloat  // relative weight; equal bands all use 1.0
    }
    enum Orientation { case horizontal, vertical }
    enum Overlay {
        /// Filled circle; cx/cy/r are normalised to [0,1] relative to the symbol rect.
        case circle(color: NSColor, cx: CGFloat, cy: CGFloat, r: CGFloat)
        /// Horizontal + vertical bars (simplified cross / St George).
        case cross(h: NSColor, v: NSColor)
        /// Filled 5-point star; cx/cy/r normalised.
        case star(color: NSColor, cx: CGFloat, cy: CGFloat, r: CGFloat)
        /// Yin-yang circle (red top-half, blue bottom-half) centred, r normalised.
        case yinYang(top: NSColor, bottom: NSColor, r: CGFloat)
    }
    let bands: [Band]
    let orientation: Orientation
    let overlay: Overlay?
}
```

### Step 3: Add `flagPattern` computed property to `WhisperLanguage`

At the end of `WhisperLanguage`, after `var displayName`, add:

```swift
    /// Simplified flag pattern for the menu bar icon, or `nil` for auto-detect.
    var flagPattern: FlagPattern? {
        switch self {
        case .auto:
            return nil

        // ── Vertical tricolours ─────────────────────────────────────────────
        case .french:
            return FlagPattern(
                bands: [.init(color: NSColor(r:0,g:85,b:164), weight:1),
                        .init(color:.white, weight:1),
                        .init(color: NSColor(r:239,g:65,b:53), weight:1)],
                orientation: .vertical, overlay: nil)
        case .italian:
            return FlagPattern(
                bands: [.init(color: NSColor(r:0,g:146,b:70), weight:1),
                        .init(color:.white, weight:1),
                        .init(color: NSColor(r:206,g:43,b:55), weight:1)],
                orientation: .vertical, overlay: nil)

        // ── Horizontal tricolours ───────────────────────────────────────────
        case .german:
            return FlagPattern(
                bands: [.init(color: NSColor(r:0,g:0,b:0), weight:1),
                        .init(color: NSColor(r:221,g:0,b:0), weight:1),
                        .init(color: NSColor(r:255,g:206,b:0), weight:1)],
                orientation: .horizontal, overlay: nil)
        case .russian:
            return FlagPattern(
                bands: [.init(color:.white, weight:1),
                        .init(color: NSColor(r:0,g:57,b:166), weight:1),
                        .init(color: NSColor(r:213,g:43,b:30), weight:1)],
                orientation: .horizontal, overlay: nil)
        case .dutch:
            return FlagPattern(
                bands: [.init(color: NSColor(r:174,g:28,b:40), weight:1),
                        .init(color:.white, weight:1),
                        .init(color: NSColor(r:33,g:70,b:139), weight:1)],
                orientation: .horizontal, overlay: nil)
        case .arabic:  // Pan-Arab (widely recognised: black, white, green)
            return FlagPattern(
                bands: [.init(color: NSColor(r:0,g:0,b:0), weight:1),
                        .init(color:.white, weight:1),
                        .init(color: NSColor(r:0,g:122,b:61), weight:1)],
                orientation: .horizontal, overlay: nil)
        case .portuguese:
            return FlagPattern(
                bands: [.init(color: NSColor(r:0,g:102,b:0), weight:2),
                        .init(color: NSColor(r:255,g:0,b:0), weight:3)],
                orientation: .vertical, overlay: nil)

        // ── Spanish (wider middle band) ────────────────────────────────────
        case .spanish:
            return FlagPattern(
                bands: [.init(color: NSColor(r:196,g:30,b:58), weight:1),
                        .init(color: NSColor(r:255,g:196,b:0), weight:2),
                        .init(color: NSColor(r:196,g:30,b:58), weight:1)],
                orientation: .horizontal, overlay: nil)

        // ── English (simplified Union Jack: blue + cross) ──────────────────
        case .english:
            return FlagPattern(
                bands: [.init(color: NSColor(r:1,g:33,b:105), weight:1)],  // solid blue bg
                orientation: .vertical,
                overlay: .cross(h: NSColor(r:200,g:16,b:46), v: NSColor(r:200,g:16,b:46)))

        // ── Japanese (white + red circle) ─────────────────────────────────
        case .japanese:
            return FlagPattern(
                bands: [.init(color:.white, weight:1)],
                orientation: .vertical,
                overlay: .circle(color: NSColor(r:188,g:0,b:45), cx:0.5, cy:0.5, r:0.28))

        // ── Chinese (red + yellow star) ────────────────────────────────────
        case .chinese:
            return FlagPattern(
                bands: [.init(color: NSColor(r:222,g:41,b:16), weight:1)],
                orientation: .vertical,
                overlay: .star(color: NSColor(r:255,g:217,b:0), cx:0.25, cy:0.72, r:0.22))

        // ── Korean (white + yin-yang) ─────────────────────────────────────
        case .korean:
            return FlagPattern(
                bands: [.init(color:.white, weight:1)],
                orientation: .vertical,
                overlay: .yinYang(top: NSColor(r:205,g:46,b:58), bottom: NSColor(r:0,g:71,b:160), r:0.28))
        }
    }
```

### Step 4: Build and verify

```bash
cd Whisperer && swift build 2>&1 | grep -E "error:|warning:" | head -20
```
Expected: 0 errors. Some warnings about the `AppKit` import at module level are OK.

### Step 5: Commit

```bash
git add Whisperer/Sources/Whisper/WhisperModels.swift
git commit -m "feat: add FlagPattern struct and flagPattern to WhisperLanguage"
```

---

## Task 2: Update `MenuBarIconState` to render flag-coloured icon

**Files:**
- Modify: `Whisperer/Sources/UI/MenuBarIconView.swift`

### Step 1: Add `language` property to `MenuBarIconState`

In `MenuBarIconState`, after the `isMeetingProcessing` property (line ~13), add:

```swift
    var language: WhisperLanguage = .auto { didSet { rebuildImage() } }
```

### Step 2: Update `rebuildImage()` to pass `language`

Change the single `rebuildImage()` call to pass `language`:

```swift
    // Replace:
    image = Self.renderIcon(dotColor: dotColor)
    // With:
    image = Self.renderIcon(dotColor: dotColor, language: language)
```

### Step 3: Replace `renderIcon` with flag-aware version

Replace the entire `renderIcon` static method with:

```swift
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

    /// Existing dot-only rendering extracted for reuse.
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
            // bands[0] = visual top; CG y=0 is bottom, so iterate top-down from maxY
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
            ctx.fillEllipse(in: CGRect(x: rect.minX + cx * rect.width - cr,
                                       y: rect.minY + cy * rect.height - cr,
                                       width: cr * 2, height: cr * 2))

        case .cross(let h, let v):
            let thick = rect.width * 0.22
            ctx.setFillColor(h.cgColor)
            ctx.fill(CGRect(x: rect.minX, y: rect.midY - thick/2, width: rect.width, height: thick))
            ctx.setFillColor(v.cgColor)
            ctx.fill(CGRect(x: rect.midX - thick/2, y: rect.minY, width: thick, height: rect.height))

        case .star(let color, let cx, let cy, let r):
            let starR = r * min(rect.width, rect.height)
            let px = rect.minX + cx * rect.width
            let py = rect.minY + cy * rect.height
            ctx.setFillColor(color.cgColor)
            var path = CGMutablePath()
            for i in 0..<5 {
                let angle = CGFloat(i) * 4 * .pi / 5 - .pi / 2
                let innerAngle = angle + 2 * .pi / 5
                let outerPt = CGPoint(x: px + cos(angle) * starR, y: py + sin(angle) * starR)
                let innerPt = CGPoint(x: px + cos(innerAngle) * starR * 0.4, y: py + sin(innerAngle) * starR * 0.4)
                if i == 0 { path.move(to: outerPt) } else { path.addLine(to: outerPt) }
                path.addLine(to: innerPt)
            }
            path.closeSubpath()
            ctx.addPath(path)
            ctx.fillPath()

        case .yinYang(let top, let bottom, let r):
            let yr = r * min(rect.width, rect.height)
            let cx2 = rect.midX
            let cy2 = rect.midY
            // Bottom half (screen bottom = CG lower)
            ctx.setFillColor(bottom.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx2 - yr, y: cy2 - yr, width: yr*2, height: yr*2))
            // Top half
            ctx.setFillColor(top.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx2 - yr, y: cy2, width: yr*2, height: yr))
            // Small circles for classic yin-yang look
            ctx.setFillColor(top.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx2 - yr/2, y: cy2 + yr/4, width: yr/2, height: yr/2))
            ctx.setFillColor(bottom.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx2, y: cy2 - yr*3/4, width: yr/2, height: yr/2))
        }
    }
```

### Step 4: Update `MenuBarIconView` to accept and forward `language`

Replace the struct definition:

```swift
// Replace:
struct MenuBarIconView: View {
    let isMeetingRecording: Bool
    let isRecording: Bool
    let isProcessing: Bool
    let isMeetingProcessing: Bool
// With:
struct MenuBarIconView: View {
    let isMeetingRecording: Bool
    let isRecording: Bool
    let isProcessing: Bool
    let isMeetingProcessing: Bool
    let language: WhisperLanguage
```

Add the onChange handler after the existing four, inside `body`:

```swift
    .onChange(of: language, initial: true) { _, val in iconState.language = val }
```

### Step 5: Build

```bash
cd Whisperer && swift build 2>&1 | grep "error:" | head -20
```
Expected: 0 errors.

### Step 6: Commit

```bash
git add Whisperer/Sources/UI/MenuBarIconView.swift
git commit -m "feat: render flag pattern through waveform in menu bar icon"
```

---

## Task 3: Wire `selectedLanguage` into `MenuBarIconView` in `WhispererApp.swift`

**Files:**
- Modify: `Whisperer/Sources/App/WhispererApp.swift` (line ~140)

### Step 1: Pass `language` to `MenuBarIconView`

Find the `MenuBarIconView(...)` call in `WhispererApp.swift` and add the `language` argument:

```swift
// Replace:
MenuBarIconView(
    isMeetingRecording: appState.isMeetingRecording,
    isRecording: appState.isRecording,
    isProcessing: appState.isProcessing,
    isMeetingProcessing: appState.isMeetingProcessing
)
// With:
MenuBarIconView(
    isMeetingRecording: appState.isMeetingRecording,
    isRecording: appState.isRecording,
    isProcessing: appState.isProcessing,
    isMeetingProcessing: appState.isMeetingProcessing,
    language: settingsStore.selectedLanguage
)
```

### Step 2: Build and run

```bash
cd Whisperer && swift run MacWhisperer
```

Open the menu bar — the waveform icon should now reflect the active language. Switch languages from the Language section in the dropdown to verify the icon updates.

**Checklist:**
- [ ] Auto → white template icon (unchanged)
- [ ] French → blue/white/red vertical stripes through waveform
- [ ] German → black/red/yellow horizontal bands through waveform
- [ ] Japanese → white waveform with red circle
- [ ] English → blue waveform with red cross
- [ ] Recording dot still shows on top when recording

### Step 3: Commit

```bash
git add Whisperer/Sources/App/WhispererApp.swift
git commit -m "feat: pass selectedLanguage to MenuBarIconView"
```

---

## Task 4: Add `cycleLanguage` keyboard shortcut

**Files:**
- Modify: `Whisperer/Sources/Settings/SettingsView.swift` (lines 6–9, ~156)
- Modify: `Whisperer/Sources/App/AppState.swift` (lines ~196–212)

### Step 1: Register the shortcut name

In `SettingsView.swift`, add to the `KeyboardShortcuts.Name` extension (line 7–8):

```swift
extension KeyboardShortcuts.Name {
    static let holdToRecord = Self("holdToRecord")
    static let meetingRecord = Self("meetingRecord")
    static let cycleLanguage = Self("cycleLanguage")  // NEW
}
```

### Step 2: Add recorder in Settings UI

After `KeyboardShortcuts.Recorder(for: .holdToRecord)` (around line 156), add a new section before the `Divider()`:

```swift
                KeyboardShortcuts.Recorder(for: .holdToRecord)

                Divider()  // existing

                VStack(alignment: .leading, spacing: 4) {
                    Label(L10n.language, systemImage: "globe")
                        .font(.headline)
                    Text("Cycle through preferred languages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    KeyboardShortcuts.Recorder(for: .cycleLanguage)
                }
```

### Step 3: Add `cycleLanguage()` method to `AppState`

In `AppState.swift`, add a new method just before `setupHotkey()`:

```swift
    func cycleLanguage() {
        let options: [WhisperLanguage] = [.auto] + settingsStore.preferredLanguages
        guard options.count > 1 else { return }
        let current = settingsStore.selectedLanguage
        let idx = options.firstIndex(of: current) ?? -1
        settingsStore.selectedLanguage = options[(idx + 1) % options.count]
    }
```

### Step 4: Register the hotkey in `setupHotkey()`

In `setupHotkey()`, add after the `meetingRecord` block (line ~211):

```swift
        KeyboardShortcuts.onKeyDown(for: .cycleLanguage) { [weak self] in
            Task { @MainActor in
                self?.cycleLanguage()
            }
        }
```

### Step 5: Build and run

```bash
cd Whisperer && swift run MacWhisperer
```

Go to Settings → Column 3 (Insert at Caret). The new Language cycle recorder should appear. Assign a shortcut (e.g. `⌥L`). Press it globally — the icon should cycle through languages.

**Checklist:**
- [ ] Recorder appears in Settings
- [ ] Shortcut cycles through `[auto] + preferredLanguages` in order
- [ ] Wraps around after last language
- [ ] Menu bar icon updates immediately on each cycle
- [ ] If only one language in preferred list, shortcut is a no-op

### Step 6: Commit

```bash
git add Whisperer/Sources/Settings/SettingsView.swift Whisperer/Sources/App/AppState.swift
git commit -m "feat: add cycleLanguage keyboard shortcut"
```

---

## Final verification

```bash
cd Whisperer && swift run MacWhisperer
```

Full end-to-end test:
1. Set language to French → icon shows blue/white/red
2. Start recording → red dot appears on top of the tricolour waveform
3. Stop recording → dot disappears, flag remains
4. Press cycle shortcut → language advances, icon updates
5. Switch to Auto → icon reverts to system template
