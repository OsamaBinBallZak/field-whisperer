import AppKit
import ApplicationServices

enum InsertionResult {
    case accessibilityInserted  // direct AX insert — no further action needed
    case pastedViaKeyboard      // Cmd+V simulated — target app should show the text
    case copiedToClipboard      // both methods unavailable — user must ⌘V manually
}

/// Inserts text into the app that was frontmost when recording began.
///
/// Strategy (in order):
/// 1. Snapshot current clipboard contents (for conditional restore later).
/// 2. Copy transcription to clipboard (universal failsafe).
/// 3. Try Accessibility API direct insert — works in real AppKit text controls
///    (Notes, Stickies, TextEdit, Xcode, Terminal). On success, schedule a
///    2 s deferred restore of the prior clipboard contents (gated by
///    `changeCount` so user copies during the window are preserved).
/// 4. Send Cmd+V via `postToPid` — universal fallback for apps where AX insert
///    fails or isn't supported (Slack, Claude.app, browsers, Electron apps).
///    Skipped only when the target is Finder/Desktop (would cause a pop sound).
///    **No clipboard restore on this path** — Cmd+V success is a weak signal
///    (the event posted, not necessarily processed), so the transcription
///    stays on the clipboard as a recovery net if auto-paste didn't land.
/// 5. Text is already on clipboard — user can ⌘V manually.
final class TextInserter {

    func insert(text: String, targetPid: pid_t? = nil) -> InsertionResult {
        let pasteboard = NSPasteboard.general

        // Snapshot the prior pasteboard BEFORE the write so we can restore it
        // later if paste strongly succeeds. Done before clearContents() because
        // pasteboardItems references become invalid once the pasteboard is
        // mutated — we force the data to materialise into Swift-owned copies.
        let priorItems = snapshotPasteboard(pasteboard)

        // Step 1: put text on clipboard (universal failsafe)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let postWriteChangeCount = pasteboard.changeCount

        // Step 2: try direct AX insert
        if tryAccessibilityInsert(text: text) {
            print("[Shhhcribble] ✅ Inserted via Accessibility API")
            // AX success is a strong signal — the text is committed to the
            // focused control synchronously, so the transcription no longer
            // needs to live on the clipboard. Schedule a restore of whatever
            // was there before, guarded by changeCount so we never clobber
            // something the user copied in the interim.
            scheduleClipboardRestore(priorItems: priorItems,
                                     markerChangeCount: postWriteChangeCount)
            return .accessibilityInserted
        }

        // Step 3: send Cmd+V to the specific process that was frontmost at record-start.
        // Using postToPid bypasses any focus ambiguity introduced by the floating panel.
        // Only skip Finder — it's the sole app that produces a system pop sound for
        // an unhandled paste (desktop/icon selection with nothing to paste into).
        if let pid = targetPid, !isFinderPid(pid), simulateCmdV(targetPid: pid) {
            print("[Shhhcribble] ✅ Pasted via Cmd+V to PID \(pid)")
            // Intentionally NO restore here: postToPid success just means the
            // event was queued, not that the app actually processed the paste.
            // Electron and other weird hosts can silently drop it. Leave the
            // transcription on the clipboard so the user can recover via ⌘V
            // if auto-paste didn't land.
            return .pastedViaKeyboard
        }

        print("[Shhhcribble] Text on clipboard — user must press ⌘V manually")
        return .copiedToClipboard
    }

    // MARK: - Clipboard snapshot / restore

    /// Capture the current pasteboard state as type→data dictionaries, one
    /// per item. Forces lazy data to materialise so the snapshot is decoupled
    /// from the live pasteboard and safe to reconstruct later.
    private func snapshotPasteboard(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        guard let items = pb.pasteboardItems else { return [] }
        return items.map { item in
            var kv: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types {
                if let d = item.data(forType: t) { kv[t] = d }
            }
            return kv
        }
    }

    /// Schedule restoration of the prior clipboard contents after a 2 s
    /// courtesy window. The window gives the user a chance to paste the
    /// transcription manually elsewhere before it's gone. Restore is skipped
    /// if `changeCount` has drifted — meaning the user (or another app)
    /// copied something in the meantime and we must not clobber it.
    ///
    /// Only called from the AX-insert success path. See `insert()` above for
    /// why Cmd+V and clipboard-only paths don't restore.
    private func scheduleClipboardRestore(priorItems: [[NSPasteboard.PasteboardType: Data]],
                                          markerChangeCount: Int) {
        guard !priorItems.isEmpty else { return }
        let pb = NSPasteboard.general
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard pb.changeCount == markerChangeCount else {
                print("[Shhhcribble] Clipboard restore skipped — user has copied something else since")
                return
            }
            let restored: [NSPasteboardItem] = priorItems.map { kv in
                let item = NSPasteboardItem()
                for (t, d) in kv { item.setData(d, forType: t) }
                return item
            }
            pb.clearContents()
            pb.writeObjects(restored)
            print("[Shhhcribble] ✅ Restored prior clipboard contents")
        }
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

    // MARK: - Cmd+V simulation

    @discardableResult
    private func simulateCmdV(targetPid: pid_t) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9   // V

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up   = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return false }

        down.flags = .maskCommand
        up.flags   = .maskCommand
        // Post directly to the target process — no dependency on system focus state
        down.postToPid(targetPid)
        up.postToPid(targetPid)
        return true
    }

    // MARK: - Helpers

    private func isFinderPid(_ pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder"
    }
}
