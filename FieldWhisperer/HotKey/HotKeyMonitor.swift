import AppKit
import CoreGraphics

/// Monitors the global FN key using a CGEventTap.
/// Requires the user to grant Input Monitoring permission in
/// System Settings → Privacy & Security → Input Monitoring.
final class HotKeyMonitor {

    private let onFNDown: () async -> Void
    private let onFNUp:   () async -> Void

    // fileprivate so the C callback can re-enable a disabled tap
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var selfRetain: Unmanaged<HotKeyMonitor>?
    private var fnIsDown = false

    init(onFNDown: @escaping () async -> Void,
         onFNUp:   @escaping () async -> Void) {
        self.onFNDown = onFNDown
        self.onFNUp   = onFNUp
    }

    deinit {
        stop()
    }

    // MARK: - Public API

    func start() {
        guard eventTap == nil else { return }

        // Retain self so the C callback can hold a raw pointer to us.
        selfRetain = Unmanaged.passRetained(self)
        let userInfo = selfRetain!.toOpaque()

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,           // passive – don't swallow events
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: userInfo
        )

        guard let tap = eventTap else {
            // Tap creation failed – Input Monitoring not granted.
            selfRetain?.release()
            selfRetain = nil
            print("[FieldWhisperer] ❌ CGEvent tap could not be created. " +
                  "Grant Input Monitoring permission and relaunch.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[FieldWhisperer] ✅ CGEvent tap created and enabled. FN key monitoring active.")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        selfRetain?.release()
        selfRetain = nil
    }

    // MARK: - Internal (called from C callback)

    /// Re-enable the tap after macOS auto-disables it (tapDisabledByTimeout).
    fileprivate func reEnableTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[FieldWhisperer] ⚠️ CGEvent tap was auto-disabled by macOS — re-enabled.")
    }

    fileprivate func handleFlagsChanged(flags: CGEventFlags) {
        // Log ALL flag-changed events so we can see raw values from every modifier key.
        // This lets us confirm events are arriving AND see what FN actually sends.
        print("[FieldWhisperer] flagsChanged: rawValue=0x\(String(flags.rawValue, radix: 16))" +
              " fn=\(flags.contains(.maskSecondaryFn))" +
              " shift=\(flags.contains(.maskShift))" +
              " cmd=\(flags.contains(.maskCommand))")

        // CGEventFlags.maskSecondaryFn (0x800000) is set while FN is held.
        let isFNDown = flags.contains(.maskSecondaryFn)

        if isFNDown && !fnIsDown {
            fnIsDown = true
            print("[FieldWhisperer] FN key DOWN detected")
            Task { @MainActor in await onFNDown() }
        } else if !isFNDown && fnIsDown {
            fnIsDown = false
            print("[FieldWhisperer] FN key UP detected")
            Task { @MainActor in await onFNUp() }
        }
    }
}

// MARK: - C callback (must be a free function or @convention(c))

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo = userInfo else { return nil }
    let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    // macOS auto-disables taps that are slow to respond. Re-enable immediately.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        monitor.reEnableTap()
        return nil
    }

    guard type == .flagsChanged else { return nil }
    monitor.handleFlagsChanged(flags: event.flags)
    return Unmanaged.passUnretained(event)
}
