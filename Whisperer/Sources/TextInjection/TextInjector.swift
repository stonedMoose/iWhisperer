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

    static func typeText(_ text: String) {
        let maxLength = 5000
        let truncated = String(text.prefix(maxLength))
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
