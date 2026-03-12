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
        let source = CGEventSource(stateID: .hidSystemState)

        for character in text {
            let utf16 = Array(String(character).utf16)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)

            keyDown?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUp?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)

            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)

            // Small delay to prevent overwhelming target app's event queue
            usleep(1000)
        }
    }
}
