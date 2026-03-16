# Text Cursor Indicator Positioning — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Position the recording indicator at the text cursor (caret) instead of the mouse pointer, and play an error beep if no caret is found.

**Architecture:** Add a `caretScreenPosition()` helper to `RecordingIndicator` that queries the focused app's text caret via Accessibility APIs (`AXUIElement`). Change `show()` to return `Bool` — positions panel at caret on success, beeps on failure. Update AppState callers to abort recording when `show()` returns `false`.

**Tech Stack:** Swift, Accessibility API (`AXUIElement`, `kAXBoundsForRangeParameterizedAttribute`), AppKit

---

### Task 1: Add caret position helper to RecordingIndicator

**Files:**
- Modify: `MyWhispers/Sources/UI/RecordingIndicator.swift`

Add a private static method that queries the focused app's text cursor position using the Accessibility API. Returns the caret position in AppKit screen coordinates (bottom-left origin), or `nil` if not found.

**Step 1: Add the helper method inside `RecordingIndicator` (after `hide()`, before the closing `}`)**

```swift
/// Query the focused app's text caret position via Accessibility API.
/// Returns the caret origin in AppKit screen coordinates (bottom-left origin), or nil.
private static func caretScreenPosition() -> NSPoint? {
    guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }

    let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

    var focusedValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
          let focused = focusedValue else { return nil }

    let focusedElement = focused as! AXUIElement

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
    guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect) else { return nil }

    // AX coordinates: origin at top-left of primary display
    // AppKit coordinates: origin at bottom-left of primary display
    guard let mainScreen = NSScreen.main else { return nil }
    let flippedY = mainScreen.frame.height - rect.origin.y - rect.size.height

    return NSPoint(x: rect.origin.x, y: flippedY)
}
```

**Step 2: Build and verify**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`
Expected: Build succeeds (method is private, not called yet)

**Step 3: Commit**

```bash
git add MyWhispers/Sources/UI/RecordingIndicator.swift
git commit -m "feat: add caretScreenPosition() helper using Accessibility API

Queries the focused app's text caret position via AXUIElement.
Returns AppKit screen coordinates or nil if no caret found."
```

---

### Task 2: Change show() to use caret position and return Bool

**Files:**
- Modify: `MyWhispers/Sources/UI/RecordingIndicator.swift`

Replace the current `show()` method with one that:
1. Calls `caretScreenPosition()` to get caret location
2. If found: positions panel next to the caret, returns `true`
3. If not found: plays `NSSound.beep()`, returns `false`

**Step 1: Replace the `show()` method (lines 8-38) with:**

```swift
/// Show the recording indicator near the text cursor.
/// Returns `false` (and beeps) if no text cursor is found.
@discardableResult
func show() -> Bool {
    guard window == nil else { return true }

    guard let caretPoint = Self.caretScreenPosition() else {
        NSSound.beep()
        return false
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
    panel.level = .floating
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    let hostingView = NSHostingView(rootView: RecordingWave())
    panel.contentView = hostingView
    panel.orderFrontRegardless()

    window = panel
    return true
}
```

**Step 2: Build and verify**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`
Expected: Build succeeds (callers ignore return value for now thanks to `@discardableResult`)

**Step 3: Commit**

```bash
git add MyWhispers/Sources/UI/RecordingIndicator.swift
git commit -m "feat: position recording indicator at text cursor, beep on failure

show() now queries caret position via Accessibility API instead of
using mouse pointer. Returns false and plays NSSound.beep() if no
text cursor is found."
```

---

### Task 3: Update AppState to abort recording when no caret is found

**Files:**
- Modify: `MyWhispers/Sources/App/AppState.swift`

Update `startBatchRecording()` and `startStreamingRecording()` to check the return value of `recordingIndicator.show()`. If `false`, don't start recording.

**Step 1: Update `startBatchRecording()` (currently lines 229-237)**

Replace with:

```swift
private func startBatchRecording() {
    do {
        try audioCapture.startRecording()
        guard recordingIndicator.show() else {
            audioCapture.stopRecording()
            return
        }
        isRecording = true
        Log.audio.info("Recording started (batch mode)")
    } catch {
        Log.audio.error("Failed to start recording: \(error)")
    }
}
```

Note: We start audio capture first (so we don't lose the beginning of speech), then check if we can show the indicator. If no caret, stop capture and abort. The `stopRecording()` return value is discarded (empty buffer).

**Step 2: Update `startStreamingRecording()` (currently lines 289-304)**

Replace with:

```swift
private func startStreamingRecording() {
    streamingTypedCount = 0
    lastStreamingResult = ""

    do {
        try audioCapture.startRecording()
        guard recordingIndicator.show() else {
            audioCapture.stopRecording()
            return
        }
        isRecording = true
        Log.audio.info("Recording started (streaming mode)")

        streamingLoopTask = Task {
            await streamingLoop()
        }
    } catch {
        Log.audio.error("Failed to start streaming recording: \(error)")
    }
}
```

**Step 3: Build and verify**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add MyWhispers/Sources/App/AppState.swift
git commit -m "fix: abort recording when no text cursor is found

Check recordingIndicator.show() return value before proceeding.
If no caret is found (beep plays), stop audio capture and abort."
```

---

### Task 4: Manual testing

**No code changes — just verification.**

**Step 1: Build the app**

Run: `cd /Users/julienlhermite/Projects/my-whispers/MyWhispers && swift build`

**Step 2: Test with a text field focused**

1. Open TextEdit or any text editor
2. Click to place cursor in the text area
3. Press the record hotkey
4. Verify: recording indicator appears near the text cursor (not the mouse)
5. Release and verify text appears at the cursor

**Step 3: Test with no text field focused**

1. Click on the desktop (Finder, no text field)
2. Press the record hotkey
3. Verify: system beep plays, no recording indicator appears, no recording starts

**Step 4: Test in different apps**

1. Test in Safari (URL bar and web text field)
2. Test in Terminal
3. Test in VS Code / your code editor
4. Verify indicator appears near the caret in each case
