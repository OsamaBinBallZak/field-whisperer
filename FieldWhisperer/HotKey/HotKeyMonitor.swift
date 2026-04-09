import AppKit
import CoreGraphics

/// Monitors the global FN key using a CGEventTap.
/// Requires the user to grant Input Monitoring permission in
/// System Settings → Privacy & Security → Input Monitoring.
final class HotKeyMonitor {

    private let onFNDown: () async -> Void
    private let onFNUp:   () async -> Void

    private var eventTap: CFMachPort?
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
            // The OS automatically prompts the user on the first failure.
            selfRetain?.release()
            selfRetain = nil
            print("[FieldWhisperer] CGEvent tap could not be created. " +
                  "Grant Input Monitoring permission and relaunch.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
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

    fileprivate func handleFlagsChanged(flags: CGEventFlags) {
        // CGEventFlags.maskSecondaryFn (0x800000) is set while FN is held.
        let isFNDown = flags.contains(.maskSecondaryFn)

        if isFNDown && !fnIsDown {
            fnIsDown = true
            Task { @MainActor in await onFNDown() }
        } else if !isFNDown && fnIsDown {
            fnIsDown = false
            Task { @MainActor in await onFNUp() }
        }
    }
}

// MARK: - C callback (must be a free function or @convention(c))

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard type == .flagsChanged, let userInfo, let event else {
        return event.map { Unmanaged.passUnretained($0) }
    }
    let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    monitor.handleFlagsChanged(flags: event.flags)
    return Unmanaged.passUnretained(event)
}
