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

    /// Returns true when Cmd+V should be attempted.
    ///
    /// The macOS error chime only occurs when Cmd+V lands on Finder/Desktop — no
    /// other app produces a system-level pop for an unhandled paste. So the only
    /// case we need to block is Finder-as-frontmost-app with no text field open.
    /// For every other app (Electron, native, browser) we let Cmd+V through.
    private func hasFocusedTextElement() -> Bool {
        let frontmost = NSWorkspace.shared.frontmostApplication

        // Not Finder — Electron (Slack, Claude) and native apps handle Cmd+V silently.
        // Verify at least something is focused before firing (handles "no app at all").
        guard frontmost?.bundleIdentifier == "com.apple.finder" else {
            let sys = AXUIElementCreateSystemWide()
            var raw: CFTypeRef?
            return AXUIElementCopyAttributeValue(
                sys, kAXFocusedUIElementAttribute as CFString, &raw
            ) == .success && raw != nil
        }

        // Finder is frontmost: only paste into an active text element, e.g. an
        // inline-rename field. Everything else (desktop, icon selection) → skip.
        let sys = AXUIElementCreateSystemWide()
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            sys, kAXFocusedUIElementAttribute as CFString, &raw
        ) == .success, let raw else { return false }
        let elem = raw as! AXUIElement
        var dummy: CFTypeRef?
        return AXUIElementCopyAttributeValue(elem, kAXValueAttribute as CFString, &dummy) == .success
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
