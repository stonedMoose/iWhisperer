# Recording Indicator Positioning Fix — Design

**Goal:** Fix the recording/processing wave indicator appearing in the top-left corner of the screen in VS Code and other Electron-based apps.

**Architecture:** One-file change to `RecordingIndicator.swift`. Tighten `caretScreenPosition()` to reject AX results whose converted coordinates fall outside any connected screen, then fall back to mouse cursor.

---

## Root Cause

VS Code (Electron/Chromium) returns a successful AX response for `kAXBoundsForRangeParameterizedAttribute` but with a zero-size rect at `(0, 0)`. After AppKit Y-axis flipping:

```
flippedY = screenHeight - 0 - 0 = screenHeight
→ NSPoint(x: 0, y: screenHeight)   // top-left corner
```

The existing guard `(caret.x != 0 || caret.y != 0)` passes because `y != 0`, so the mouse fallback is never reached.

## Fix

Add a screen containment check inside `caretScreenPosition()` before returning:

```swift
let converted = NSPoint(x: rect.origin.x, y: flippedY)
guard NSScreen.screens.contains(where: { $0.frame.contains(converted) }) else {
    return nil   // bad AX data → triggers mouse fallback in show()
}
return converted
```

Simplify `show()` guard (remove manual (0,0) check — now handled by screen validation):

```swift
if let caret = Self.caretScreenPosition() {
    caretPoint = caret
} else {
    caretPoint = NSEvent.mouseLocation
    Log.ui.info("Caret unavailable, falling back to mouse")
}
```

## Scope

- **File:** `Whisperer/Sources/UI/RecordingIndicator.swift`
- **Lines changed:** ~5
- **`showProcessing()`:** No change needed — panel stays at position set by `show()`
