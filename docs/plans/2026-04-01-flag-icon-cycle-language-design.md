# Design: Flag Icon + Language Cycle Shortcut

**Date:** 2026-04-01  
**Status:** Approved  

## Objective

Two linked UX improvements for MacWhisperer's menu bar:

1. **Visual feedback** — the menu bar icon shows the active language via a simplified flag pattern rendered through the waveform shape.
2. **Cycle shortcut** — a configurable global hotkey cycles through the user's preferred languages (+ auto-detect).

---

## Feature 1: Flag-Colored Menu Bar Icon

### Behaviour

| Language | Rendering |
|----------|-----------|
| `auto` | Template (white/system tint, current behaviour) |
| `fr`, `it` | 3 vertical bands (blue/white/red, green/white/red) |
| `de`, `nl`, `ru` | 3 horizontal bands |
| `es` | 3 horizontal bands, middle band wider (yellow) |
| `pt` | Vertical green + red |
| `en` | Simplified Union Jack: blue bg + red/white cross + diagonals |
| `ja` | White + red centered circle |
| `zh` | Red + small yellow star, top-left |
| `ko` | White + red/blue yin-yang circle centered |
| `ar` | 3 horizontal pan-Arab bands (black, white, green) |

When recording or processing, the state dot (red / orange) is drawn on top of the flag-coloured waveform — both indicators coexist.

### Rendering technique: texture masking

1. Render the SF Symbol "waveform" into an offscreen `CGContext` to obtain its alpha channel as a `CGImage` mask.
2. In the main compositing context, draw the flag pattern (stripes + optional overlay shape) across the full icon rect.
3. Apply `ctx.clip(to: rect, mask: waveformMask)` → flag colours show only through the waveform pixels.
4. Draw the state dot (if any) on top with normal blending.
5. `isTemplate = false` for all non-auto languages (colours must be preserved).

### Data model

Add a `flagPattern: FlagPattern?` computed property to `WhisperLanguage` (returns `nil` for `.auto`).

```swift
struct FlagPattern {
    struct Band { let color: NSColor; let weight: CGFloat }
    enum Orientation { case horizontal, vertical }
    let bands: [Band]
    let orientation: Orientation
    let overlay: Overlay?

    enum Overlay {
        case circle(color: NSColor, center: CGPoint, radius: CGFloat)  // ja
        case cross(h: NSColor, v: NSColor, diagonal: NSColor?)         // en
        case star(color: NSColor, topLeft: Bool)                       // zh
        case yinYang(top: NSColor, bottom: NSColor)                    // ko
    }
}
```

### Files changed

- `Sources/Whisper/WhisperModels.swift` — add `FlagPattern` struct + `flagPattern` property on `WhisperLanguage`
- `Sources/UI/MenuBarIconView.swift` — `MenuBarIconState` gains `var language: WhisperLanguage`; `renderIcon` gains flag masking path
- `Sources/App/WhispererApp.swift` — pass `settingsStore.selectedLanguage` into `MenuBarIconView`

---

## Feature 2: Language Cycle Shortcut

### Behaviour

- Pressing the shortcut cycles `selectedLanguage` through `[.auto] + settingsStore.preferredLanguages` in order, wrapping around.
- Works globally (system-wide hotkey via KeyboardShortcuts), identical to `holdToRecord`.
- No default binding — user assigns it in Settings.

### Cycle logic

```swift
func cycleLanguage() {
    let options: [WhisperLanguage] = [.auto] + settingsStore.preferredLanguages
    guard options.count > 1 else { return }
    let current = settingsStore.selectedLanguage
    let idx = options.firstIndex(of: current) ?? -1
    settingsStore.selectedLanguage = options[(idx + 1) % options.count]
}
```

### Files changed

- `Sources/Settings/SettingsView.swift` — add `static let cycleLanguage = Self("cycleLanguage")` to `KeyboardShortcuts.Name`; add `KeyboardShortcuts.Recorder(for: .cycleLanguage)` in the shortcuts section
- `Sources/App/AppState.swift` — add `cycleLanguage()` method; register `KeyboardShortcuts.onKeyDown(for: .cycleLanguage)` in `setupHotkey()`

---

## Non-goals

- No flag emoji or system image assets (all rendered procedurally in Core Graphics)
- No animated flag transitions
- No per-language icon caching (icons are small, re-rendering on language change is negligible)
