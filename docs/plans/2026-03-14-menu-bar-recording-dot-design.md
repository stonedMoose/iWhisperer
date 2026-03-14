# Menu Bar Recording Dot Indicator

## Goal

Show a red pulsing dot in the bottom-right of the menu bar waveform icon when a meeting is being recorded.

## Approach

Keep `MenuBarExtra` for the dropdown menu. Replace the static `systemImage: "waveform"` label with a custom `label:` closure containing an `NSViewRepresentable` that wraps an AppKit `NSImageView`. This gives full control over icon compositing and animation.

## Components

### `MenuBarIconView` (NSViewRepresentable)

- Wraps an `NSImageView` displaying the waveform SF Symbol as a template image (18x18 pt)
- Accepts binding/state for recording status: `isMeetingRecording`, `isRecording`, `isProcessing`, `isMeetingProcessing`
- When active, composites a red dot (7pt diameter) at bottom-right of the icon
- Pulsing: a `Timer` toggles dot opacity between 1.0 and 0.3 every 0.4s (0.8s full cycle)

### State-based dot behavior

| State | Dot | Animation |
|-------|-----|-----------|
| Meeting recording | Red | Pulsing |
| Regular recording | Red | Solid |
| Processing/transcribing | Orange | Solid |
| Idle | None | — |

### Integration in `MyWhispersApp.swift`

Change from:
```swift
MenuBarExtra("MyWhispers", systemImage: "waveform") { ... }
```

To:
```swift
MenuBarExtra {
    // existing menu content unchanged
} label: {
    MenuBarIconView(
        isMeetingRecording: appState.isMeetingRecording,
        isRecording: appState.isRecording,
        isProcessing: appState.isProcessing,
        isMeetingProcessing: appState.isMeetingProcessing
    )
}
```

### Files changed

- **New**: `MyWhispers/Sources/UI/MenuBarIconView.swift` — NSViewRepresentable + NSView subclass
- **Modified**: `MyWhispers/Sources/App/MyWhispersApp.swift` — swap label initializer
- **Unchanged**: `MenuBarLabel.swift` — existing SwiftUI version kept for now (can be removed later)

## Rendering detail

The NSView subclass (`StatusBarIconNSView`) overrides `draw(_:)` to:
1. Draw the waveform SF Symbol as a template image (respects menu bar appearance)
2. If recording state is active, draw a filled circle at bottom-right with appropriate color
3. Timer invalidates the view to toggle opacity for pulsing effect
