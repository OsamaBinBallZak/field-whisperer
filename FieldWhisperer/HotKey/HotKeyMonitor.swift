import Carbon.HIToolbox
import AppKit

/// Monitors a global push-to-talk hotkey using Carbon's RegisterEventHotKey.
///
/// Default hotkey: Option+Space (⌥Space)
/// - No Input Monitoring permission required
/// - Never auto-disabled by macOS
/// - keyDown fires onKeyDown; keyUp fires onKeyUp (push-to-talk style)
final class HotKeyMonitor {

    private let onFNDown: () async -> Void
    private let onFNUp:   () async -> Void

    private var hotKeyRef:    EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    // ⌥Space: change keyCode/modifiers here to use a different combo
    private let keyCode:   UInt32 = UInt32(kVK_Space)
    private let modifiers: UInt32 = UInt32(optionKey)

    init(onFNDown: @escaping () async -> Void,
         onFNUp:   @escaping () async -> Void) {
        self.onFNDown = onFNDown
        self.onFNUp   = onFNUp
    }

    deinit { stop() }

    // MARK: - Public API

    func start() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = fourCharCode("FWpt")   // FieldWhisperer push-to-talk
        hotKeyID.id        = 1

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind:  UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind:  UInt32(kEventHotKeyReleased))
        ]

        // Retain self for the C callback
        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventCallback,
            eventTypes.count,
            &eventTypes,
            selfPtr,
            &eventHandler
        )

        guard status == noErr else {
            print("[FieldWhisperer] ❌ InstallEventHandler failed: \(status)")
            Unmanaged<HotKeyMonitor>.fromOpaque(selfPtr).release()
            return
        }

        let regStatus = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetApplicationEventTarget(), 0,
            &hotKeyRef
        )

        if regStatus == noErr {
            print("[FieldWhisperer] ✅ Hotkey registered: ⌥Space (Option+Space). " +
                  "Hold to record, release to transcribe.")
        } else {
            print("[FieldWhisperer] ❌ RegisterEventHotKey failed: \(regStatus). " +
                  "Another app may already have ⌥Space. Try quitting Spotlight/Alfred/Raycast.")
        }
    }

    func stop() {
        if let ref = hotKeyRef     { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let h   = eventHandler  { RemoveEventHandler(h);      eventHandler = nil }
    }

    // MARK: - Internal (called from C callback)

    fileprivate func handleKeyDown() {
        print("[FieldWhisperer] ⌥Space DOWN — starting recording")
        Task { @MainActor in await onFNDown() }
    }

    fileprivate func handleKeyUp() {
        print("[FieldWhisperer] ⌥Space UP — stopping recording")
        Task { @MainActor in await onFNUp() }
    }
}

// MARK: - Carbon event callback

private let hotKeyEventCallback: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()

    switch Int(GetEventKind(event)) {
    case kEventHotKeyPressed:  monitor.handleKeyDown()
    case kEventHotKeyReleased: monitor.handleKeyUp()
    default: break
    }
    return noErr
}

// MARK: - Helpers

private func fourCharCode(_ s: StaticString) -> FourCharCode {
    let bytes = s.utf8Start
    return FourCharCode(bytes[0]) << 24
         | FourCharCode(bytes[1]) << 16
         | FourCharCode(bytes[2]) << 8
         | FourCharCode(bytes[3])
}
