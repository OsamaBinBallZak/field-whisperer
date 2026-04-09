import AppKit
import ApplicationServices

/// Inserts text into the currently focused UI element.
///
/// Strategy (in order):
/// 1. Accessibility API – sets the selected-text attribute of the focused AX element.
///    Works with most native macOS apps (TextEdit, Notes, Xcode, Terminal, etc.).
/// 2. Pasteboard + simulated Cmd-V – universal fallback that works in every app,
///    including Electron-based apps and web browsers.
///    The original clipboard content is restored after a short delay.
final class TextInserter {

    func insert(text: String) {
        if tryAccessibilityInsert(text: text) {
            print("[FieldWhisperer] ✅ Text inserted via Accessibility API")
            return
        }
        print("[FieldWhisperer] AX insert failed or not trusted — using pasteboard fallback (Cmd+V)")
        pasteboardInsert(text: text)
    }

    // MARK: - Primary: Accessibility API

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

    // MARK: - Fallback: Pasteboard + Cmd-V

    private func pasteboardInsert(text: String) {
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)

        // Place transcribed text on the clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Synthesize Cmd-V keyDown / keyUp
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9      // physical V key

        if let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
           let up   = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) {
            down.flags = .maskCommand
            up.flags   = .maskCommand
            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap:   .cgAnnotatedSessionEventTap)
        }

        // Restore the clipboard after 600 ms (after the paste completes)
        let changeCountAfterWrite = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            // Only restore if the clipboard hasn't been changed by the user since
            if pasteboard.changeCount == changeCountAfterWrite {
                pasteboard.clearContents()
                if let prev = previousContent {
                    pasteboard.setString(prev, forType: .string)
                }
            }
        }
    }
}
