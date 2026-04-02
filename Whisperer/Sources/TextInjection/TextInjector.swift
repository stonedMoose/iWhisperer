import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
struct TextInjector {

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        )
    }

    static func requestAccessibilityPermission() {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )
    }

    /// Injects text by placing it on the clipboard and simulating Cmd+V.
    /// This makes all text appear at once instead of character-by-character.
    static func typeText(_ text: String) async {
        let maxLength = 5000
        let sanitized = String(text.prefix(maxLength)).filter { char in
            char == "\n" || char == "\t" || (char >= " " && char != "\u{7F}")
        }
        guard !sanitized.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let savedContent = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(sanitized, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9 // 'v'
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        // Wait for the target app to process the paste before restoring the clipboard.
        try? await Task.sleep(for: .milliseconds(100))

        pasteboard.clearContents()
        if let saved = savedContent {
            pasteboard.setString(saved, forType: .string)
        }
    }
}
