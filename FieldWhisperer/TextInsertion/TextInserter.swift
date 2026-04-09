import AppKit
import ApplicationServices

/// Result of a text insertion attempt.
enum InsertionResult {
    case accessibilityInserted   // AX API worked — text also on clipboard as bonus
    case copiedToClipboard       // AX failed — text on clipboard, user must ⌘V
}

/// Inserts text into the currently focused UI element.
///
/// Strategy:
/// 1. Always copy text to the clipboard (failsafe — user can always ⌘V).
/// 2. Try Accessibility API to insert directly into the focused field.
/// 3. If AX fails, the text is already on the clipboard — caller shows "Copied!" feedback.
final class TextInserter {

    func insert(text: String) -> InsertionResult {
        // Always put text on clipboard as a failsafe
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Try the Accessibility path for direct insertion
        if tryAccessibilityInsert(text: text) {
            print("[FieldWhisperer] ✅ Text inserted via Accessibility API (also on clipboard)")
            return .accessibilityInserted
        }

        print("[FieldWhisperer] AX insert not available — text copied to clipboard (⌘V to paste)")
        return .copiedToClipboard
    }

    // MARK: - Accessibility API

    private func tryAccessibilityInsert(text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let systemElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        let copyResult = AXUIElementCopyAttributeValue(
            systemElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard copyResult == .success, let element = focusedElement else { return false }

        // Verify the element accepts text input before setting
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element as! AXUIElement,
                                       kAXSelectedTextAttribute as CFString,
                                       &settable)
        guard settable.boolValue else { return false }

        let setResult = AXUIElementSetAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        return setResult == .success
    }
}
