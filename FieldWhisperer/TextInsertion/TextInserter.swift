import AppKit
import ApplicationServices

enum InsertionResult {
    case accessibilityInserted  // direct AX insert — no further action needed
    case pastedViaKeyboard      // Cmd+V simulated — target app should show the text
    case copiedToClipboard      // both methods unavailable — user must ⌘V manually
}

/// Inserts text into the currently focused UI element.
///
/// Strategy (in order):
/// 1. Always copy to clipboard (universal failsafe).
/// 2. Try Accessibility API (direct insert — works in Notes, TextEdit, Xcode, Terminal…).
/// 3. Simulate Cmd+V (works in Slack, Claude, browsers, Electron apps).
///    If this fires, the caller shows a brief "Pasted!" confirmation.
/// 4. If all else fails, text is already on clipboard — caller shows "Copied! ⌘V".
final class TextInserter {

    func insert(text: String) -> InsertionResult {
        // Step 1: always put text on clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Step 2: try direct AX insert
        if tryAccessibilityInsert(text: text) {
            print("[FieldWhisperer] ✅ Inserted via Accessibility API")
            return .accessibilityInserted
        }

        // Step 3: simulate Cmd+V — but only when there's a focused text element.
        // Without this guard, Cmd+V lands in Finder/desktop and macOS plays a pop sound.
        if hasFocusedTextElement(), simulateCmdV() {
            print("[FieldWhisperer] ✅ Pasted via Cmd+V simulation")
            return .pastedViaKeyboard
        }

        print("[FieldWhisperer] Text on clipboard — user must press ⌘V manually")
        return .copiedToClipboard
    }

    // MARK: - Accessibility API

    private func tryAccessibilityInsert(text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let systemElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            systemElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success, let element = focusedElement else { return false }

        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element as! AXUIElement,
                                       kAXSelectedTextAttribute as CFString,
                                       &settable)
        guard settable.boolValue else { return false }

        return AXUIElementSetAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success
    }

    // MARK: - Focus check

    /// Returns true if the system-wide focused element is a text-editing context.
    /// Prevents Cmd+V from firing into Finder/desktop (which triggers a pop sound).
    /// Three-layer check covers: native apps, Electron apps (Slack, Claude), and empty fields.
    private func hasFocusedTextElement() -> Bool {
        let sys = AXUIElementCreateSystemWide()
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            sys, kAXFocusedUIElementAttribute as CFString, &raw
        ) == .success, let raw else { return false }
        let elem = raw as! AXUIElement

        var dummy: CFTypeRef?
        // kAXValueAttribute — native text fields (Notes, TextEdit, Xcode, Terminal)
        if AXUIElementCopyAttributeValue(elem, kAXValueAttribute as CFString, &dummy) == .success {
            return true
        }
        // "AXSelectedTextRange" — Electron/browser apps (Slack, Claude) expose this when
        // a contenteditable or input element is focused inside the Chromium web layer
        if AXUIElementCopyAttributeValue(elem, "AXSelectedTextRange" as CFString, &dummy) == .success {
            return true
        }
        // Role-based fallback: empty native fields may not expose kAXValueAttribute
        if AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &dummy) == .success,
           let role = dummy as? String,
           ["AXTextField", "AXTextArea", "AXComboBox"].contains(role) {
            return true
        }
        return false
    }

    // MARK: - Cmd+V simulation

    @discardableResult
    private func simulateCmdV() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9   // V

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up   = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return false }

        down.flags = .maskCommand
        up.flags   = .maskCommand
        // .cgSessionEventTap injects at session level — reaches the frontmost app
        down.post(tap: .cgSessionEventTap)
        up.post(tap:   .cgSessionEventTap)
        return true
    }
}
