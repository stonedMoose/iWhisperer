import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
struct TextInjector {

    /// Check if the app has Accessibility permission.
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        )
    }

    /// Prompt the user to grant Accessibility permission.
    static func requestAccessibilityPermission() {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )
    }

    /// Type text at the current cursor position using CGEvent keyboard simulation.
    static func typeText(_ text: String) {
        let maxLength = 5000
        let truncated = String(text.prefix(maxLength))
        // Strip control characters (keep printable, space, newline, tab)
        let sanitized = truncated.filter { char in
            char == "\n" || char == "\t" || (char >= " " && char != "\u{7F}")
        }

        let source = CGEventSource(stateID: .hidSystemState)

        for character in sanitized {
            let utf16 = Array(String(character).utf16)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)

            keyDown?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUp?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)

            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)

            usleep(1000)
        }
    }
}
