import CoreAudio
import Foundation
import os

/// Pauses Spotify and Apple Music during recording, resumes them on stop.
/// Uses AppleScript directly to each app — no private APIs, no Bluetooth
/// audio bridge, no system-volume side effects. Works identically on
/// AirPods, built-in speakers, USB DACs, and HDMI.
///
/// **Coverage scope:** Spotify and Apple Music only. YouTube and other
/// browser-tab audio are NOT paused — the user accepted this trade-off
/// (Spotify is the dominant use case). Layering browser-tab JS injection
/// on top is possible later without changing the Spotify path.
///
/// **Why not MediaRemote / Now Playing:** The previous iteration tried
/// `MRMediaRemoteGetNowPlayingApplicationIsPlaying`, which Apple
/// progressively locked down starting in macOS 15.4. On macOS 26 the
/// IsPlaying call returns `false` even when Spotify is actively playing,
/// making the entire pause-detection unusable. AppleScript is the
/// deterministic alternative — slightly more permission friction (one TCC
/// prompt per app first time), but it works.
///
/// **Why not just send media keys:** Sending Pause unconditionally risks
/// ambiguity on resume — if the user had paused Spotify themselves, we'd
/// send Play and start music they'd intentionally silenced. AppleScript
/// asks "are you currently playing?" first, so we only resume what we
/// paused.
@MainActor
final class MusicPauser {

    private static let logger = Logger(subsystem: "com.shhhcribble.app", category: "pauser")

    /// Per-app state — independent flags so we resume only what we paused.
    /// Multiple apps can be playing simultaneously; we handle them as a set.
    private var pausedApps: Set<TargetApp> = []

    private enum TargetApp: String, CaseIterable {
        case spotify = "Spotify"
        case music   = "Music"
    }

    func pauseIfPlaying() {
        for app in TargetApp.allCases {
            if pauseIfPlaying(app) {
                pausedApps.insert(app)
            }
        }
    }

    func resumeIfPaused() {
        for app in pausedApps {
            resume(app)
        }
        pausedApps.removeAll()
    }

    /// Schedules `resumeIfPaused()` to fire once the audio system has
    /// settled, so music doesn't collide with the scribble chime or — on
    /// AirPods — play briefly through the still-active mic codec (HFP)
    /// before the route switches back to A2DP.
    ///
    /// On Bluetooth outputs: 2100 ms fixed delay. Sized to clear the full
    /// HFP→A2DP transition plus buffer flush. We tried a `kAudioDevicePropertyNominalSampleRate`
    /// listener to resume early when the codec switch fires, but it never
    /// fires on AirPods in practice — the default output device swaps
    /// between A2DP and HFP virtual devices, leaving our listener attached
    /// to one that's no longer current. Fixed delay is simpler and
    /// behaviorally identical.
    ///
    /// On non-Bluetooth outputs: 700 ms — no codec switch to wait on, just
    /// the chime/paste breathing room.
    ///
    /// Fire-and-forget. Safe to call when nothing is paused (no-op).
    func scheduleResumeAfterOutputSettles() {
        guard !pausedApps.isEmpty else {
            Self.logger.notice("scheduleResume: nothing paused — no-op")
            return
        }

        let isBluetooth = Self.defaultOutputDevice().map { Self.isBluetoothDevice($0) } ?? false
        let delayMs = isBluetooth ? 2100 : 700
        Self.logger.notice("scheduleResume: \(isBluetooth ? "BT" : "non-BT", privacy: .public) output — \(delayMs)ms delay")

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMs))
            await MainActor.run { self?.resumeIfPaused() }
        }
    }

    // MARK: - Per-app actions

    /// Returns true iff the app was running, was playing, and we paused it.
    /// Returns false if the app isn't running, isn't playing, or AppleScript
    /// errored (e.g., user denied TCC).
    private func pauseIfPlaying(_ app: TargetApp) -> Bool {
        // The `running` guard avoids launching the app just to query state.
        // The `player state is playing` guard avoids the case where the user
        // has the app open but already paused — we don't want to send pause
        // again (no-op, but also nothing to track for resume).
        let source = """
        if application "\(app.rawValue)" is running then
            tell application "\(app.rawValue)"
                if player state is playing then
                    pause
                    return "paused"
                end if
            end tell
        end if
        return "no"
        """
        let result = run(source, label: "pause \(app.rawValue)")
        let paused = (result == "paused")
        Self.logger.notice("pause \(app.rawValue, privacy: .public): \(paused ? "paused" : "skipped", privacy: .public)")
        return paused
    }

    private func resume(_ app: TargetApp) {
        // No state check on resume: telling Spotify/Music to "play" while
        // already playing is a no-op in both apps, so we don't risk
        // double-starting anything. Keeping this simple — the per-app
        // flag in pausedApps already gates whether we attempt resume at all.
        let source = """
        if application "\(app.rawValue)" is running then
            tell application "\(app.rawValue)" to play
        end if
        """
        _ = run(source, label: "resume \(app.rawValue)")
        Self.logger.notice("resume \(app.rawValue, privacy: .public): sent")
    }

    // MARK: - AppleScript runner

    /// Runs an AppleScript synchronously and returns its string result, or
    /// nil on error. Errors are logged at .error so a denied-TCC prompt or
    /// app crash shows up in `log stream`.
    @discardableResult
    private func run(_ source: String, label: String) -> String? {
        guard let script = NSAppleScript(source: source) else {
            Self.logger.error("\(label, privacy: .public): NSAppleScript init failed")
            return nil
        }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error = error {
            // -1743 = "Not authorised" (TCC denied or not yet granted).
            // -600  = "Application isn't running" — race; treat as benign.
            // Anything else gets surfaced verbatim for debugging.
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            let message = (error[NSAppleScript.errorMessage] as? String) ?? "unknown"
            Self.logger.error("\(label, privacy: .public): error \(code, privacy: .public) — \(message, privacy: .public)")
            return nil
        }
        return descriptor.stringValue
    }

    // MARK: - Core Audio: output device transport

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    private static func isBluetoothDevice(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)
        guard status == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
    }
}
