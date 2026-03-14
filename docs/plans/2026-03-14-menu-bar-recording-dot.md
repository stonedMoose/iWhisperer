# Menu Bar Recording Dot Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Show a red pulsing dot over the menu bar waveform icon when a meeting is being recorded.

**Architecture:** Create an `NSViewRepresentable` wrapping a custom `NSView` that draws the SF Symbol waveform icon + a colored dot overlay. The dot pulses via a `Timer` during meeting recording. Integrate into `MenuBarExtra`'s label closure, keeping the existing `.menu` style dropdown unchanged.

**Tech Stack:** SwiftUI (MenuBarExtra label), AppKit (NSView custom drawing), SF Symbols

---

### Task 1: Create MenuBarIconView (NSViewRepresentable + NSView)

**Files:**
- Create: `MyWhispers/Sources/UI/MenuBarIconView.swift`

**Step 1: Create the file with the NSView subclass**

The `StatusBarIconNSView` handles all drawing. It renders the waveform SF Symbol as a template image, then overlays a colored dot at bottom-right when in a recording/processing state. A timer toggles dot opacity for pulsing.

```swift
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

        // Draw waveform SF Symbol as template image
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        guard let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "MyWhispers")?
            .withSymbolConfiguration(config) else { return }

        image.isTemplate = true
        let imageSize = image.size
        let x = (bounds.width - imageSize.width) / 2
        let y = (bounds.height - imageSize.height) / 2
        image.draw(in: NSRect(x: x, y: y, width: imageSize.width, height: imageSize.height))

        // Draw dot overlay
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

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        dotVisible = true
    }
}
```

**Step 2: Add the NSViewRepresentable wrapper below in the same file**

```swift
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
```

**Step 3: Commit**

```bash
git add MyWhispers/Sources/UI/MenuBarIconView.swift
git commit -m "feat: add MenuBarIconView with AppKit-based recording dot"
```

---

### Task 2: Wire MenuBarIconView into MenuBarExtra

**Files:**
- Modify: `MyWhispers/Sources/App/MyWhispersApp.swift:17`

**Step 1: Change the MenuBarExtra initializer**

Replace line 17:
```swift
MenuBarExtra("MyWhispers", systemImage: "waveform") {
```

With the label-based initializer:
```swift
MenuBarExtra {
```

And after the closing `}` of the menu content (before `.menuBarExtraStyle(.menu)`), add the label closure:
```swift
} label: {
    MenuBarIconView(
        isMeetingRecording: appState.isMeetingRecording,
        isRecording: appState.isRecording,
        isProcessing: appState.isProcessing,
        isMeetingProcessing: appState.isMeetingProcessing
    )
}
```

The full structure becomes:
```swift
MenuBarExtra {
    // ... all existing menu content stays exactly the same ...
} label: {
    MenuBarIconView(
        isMeetingRecording: appState.isMeetingRecording,
        isRecording: appState.isRecording,
        isProcessing: appState.isProcessing,
        isMeetingProcessing: appState.isMeetingProcessing
    )
}
.menuBarExtraStyle(.menu)
```

**Step 2: Build and verify**

Run: `cd MyWhispers && swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add MyWhispers/Sources/App/MyWhispersApp.swift
git commit -m "feat: wire MenuBarIconView into MenuBarExtra label"
```

---

### Task 3: Manual smoke test

**Step 1: Run the app**

Run: `cd MyWhispers && swift run`

**Step 2: Verify these behaviors visually**

1. **Idle**: Waveform icon visible in menu bar, no dot
2. **Meeting recording**: Start a meeting recording via the menu — red dot appears at bottom-right, pulsing between full and dim opacity
3. **Meeting processing**: Stop the meeting — dot turns orange, solid
4. **Regular recording**: Hold the record hotkey — solid red dot appears
5. **Menu**: Click the icon — dropdown menu still works normally

**Step 3: If all good, commit any adjustments**

If dot positioning or sizing needs tweaking, adjust `dotSize`, `dotRect` coordinates, or SF Symbol `pointSize` in `StatusBarIconNSView.draw(_:)`.

---

### Task 4: Clean up (optional)

**Files:**
- Consider: `MyWhispers/Sources/UI/MenuBarLabel.swift`

The old `MenuBarLabel` SwiftUI view is now unused. It can be deleted if confirmed unused elsewhere.

**Step 1: Search for usages**

Run: `grep -r "MenuBarLabel" MyWhispers/Sources/`
Expected: Only the definition in `MenuBarLabel.swift`, no usages

**Step 2: Delete if unused**

```bash
rm MyWhispers/Sources/UI/MenuBarLabel.swift
git add -u MyWhispers/Sources/UI/MenuBarLabel.swift
git commit -m "chore: remove unused MenuBarLabel SwiftUI view"
```
