# Text Cursor Indicator Positioning — Design

**Problem:** The recording indicator currently appears at the mouse pointer position (`NSEvent.mouseLocation`). It should appear at the text cursor (caret) in the focused text field.

**Approach:** Use the Accessibility API (`AXUIElement`) to query the focused app's text field for the caret position via `kAXSelectedTextRangeAttribute` + `kAXBoundsForRangeParameterizedAttribute`.

**Changes:**

1. **`RecordingIndicator.show()` → `show() -> Bool`**
   - Query focused element's caret position via AXUIElement
   - If found: position panel next to caret rect, return `true`
   - If not found: play `NSSound.beep()`, return `false`

2. **`AppState.startBatchRecording()` / `startStreamingRecording()`**
   - Check return value of `recordingIndicator.show()`
   - If `false`: don't start recording (no text cursor = nowhere to type)

**Caret position query:**
- `NSWorkspace.shared.frontmostApplication` → pid
- `AXUIElementCreateApplication(pid)` → app element
- `kAXFocusedUIElementAttribute` → focused element
- `kAXSelectedTextRangeAttribute` → text range (CFRange)
- `kAXBoundsForRangeParameterizedAttribute(range)` → CGRect in screen coords

**Fallback:** If any AX query fails → `NSSound.beep()`, return `false`.

**No custom audio:** Uses `NSSound.beep()` — standard macOS alert sound.
