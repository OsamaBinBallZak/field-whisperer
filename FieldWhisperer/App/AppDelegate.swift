import AppKit
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var hotKeyMonitor: HotKeyMonitor!
    private var audioRecorder: AudioRecorder!
    private var transcriptionEngine: TranscriptionEngine!
    private var textInserter: TextInserter!
    private var soundwavePanel: SoundwavePanel!
    private var menuBarController: MenuBarController!
    private var settingsWindowController: SettingsWindowController?

    private enum AppState { case idle, recording, transcribing }
    private var state: AppState = .idle

    /// PID of the app that was frontmost when recording began — captured before
    /// the floating panel appears so Cmd+V can be targeted precisely at that process.
    private var insertionTargetPid: pid_t? = nil

    // Live transcription: runs WhisperKit on the growing buffer every N seconds
    private var liveTranscriptionTask: Task<Void, Never>?
    private let liveTranscriptionInterval: TimeInterval = 3.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[FieldWhisperer] App launched.")

        let axTrusted = requestAccessibilityPermission()
        print("[FieldWhisperer] AXIsProcessTrusted = \(axTrusted)")

        transcriptionEngine = TranscriptionEngine()
        audioRecorder       = AudioRecorder()
        textInserter        = TextInserter()

        let soundwaveViewModel = SoundwaveViewModel()
        soundwavePanel = SoundwavePanel(viewModel: soundwaveViewModel)

        menuBarController = MenuBarController(
            transcriptionEngine: transcriptionEngine,
            delegate: self
        )

        Task {
            await transcriptionEngine.loadModel(variant: ModelManager.selectedModel)
            menuBarController.rebuildMenu()
        }

        let hotkey = ModelManager.selectedHotkey
        hotKeyMonitor = HotKeyMonitor(
            onKeyDown: { [weak self] in await self?.beginRecording() },
            onKeyUp:   { [weak self] in await self?.endRecording()   }
        )
        hotKeyMonitor.start(keyCode: hotkey.keyCode, modifiers: hotkey.modifiers)
    }

    // MARK: - Recording state machine

    private func beginRecording() async {
        guard state == .idle else { return }
        guard transcriptionEngine.isReady else {
            print("[FieldWhisperer] Model not ready: \(transcriptionEngine.statusText)")
            menuBarController.flashNotReady()
            return
        }
        print("[FieldWhisperer] Recording started")
        state = .recording
        // Capture before the panel appears — frontmostApplication is accurate here
        insertionTargetPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        soundwavePanel.show()
        menuBarController.setRecordingIndicator(active: true)
        audioRecorder.start { [weak self] level in
            self?.soundwavePanel.updateLevel(level)
        }
        startLiveTranscription()
    }

    private func endRecording() async {
        guard state == .recording else { return }
        stopLiveTranscription()

        state = .transcribing
        let samples = audioRecorder.stop()
        print("[FieldWhisperer] Captured \(samples.count) samples (~\(String(format: "%.1f", Double(samples.count)/16000))s)")
        soundwavePanel.showTranscribing()
        menuBarController.setRecordingIndicator(active: false)

        var textToInsert: String? = nil
        do {
            let text = try await transcriptionEngine.transcribe(audioSamples: samples)
            var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if ModelManager.fillerFilterEnabled {
                trimmed = FillerWordFilter.filter(trimmed)
            }
            textToInsert = trimmed.isEmpty ? nil : trimmed
        } catch {
            print("[FieldWhisperer] ❌ Transcription error: \(error.localizedDescription)")
        }

        guard let text = textToInsert else {
            soundwavePanel.hide()
            state = .idle
            return
        }

        // Save to history and refresh menu before inserting
        ModelManager.addToHistory(text)
        menuBarController.rebuildMenu()

        print("[FieldWhisperer] Inserting: \"\(text.prefix(80))\"")

        // Panel stays visible (nonactivating — target app keeps focus).
        // Small delay lets any focus changes settle before the insert.
        try? await Task.sleep(for: .milliseconds(150))

        let _ = textInserter.insert(text: text, targetPid: insertionTargetPid)
        insertionTargetPid = nil

        // Always show completion feedback then auto-hide with exit animation
        soundwavePanel.showCopied()

        state = .idle
    }

    // MARK: - Live transcription

    private func startLiveTranscription() {
        liveTranscriptionTask = Task { [weak self] in
            guard let self else { return }
            // Wait a beat before the first pass so there's audio to transcribe
            try? await Task.sleep(for: .seconds(liveTranscriptionInterval))

            while !Task.isCancelled, self.state == .recording {
                let snapshot = self.audioRecorder.currentSamples
                // Need at least 1s of audio before attempting live transcription
                if snapshot.count > 16_000 {
                    if let text = try? await self.transcriptionEngine.transcribe(audioSamples: snapshot) {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            self.soundwavePanel.updateLiveText(trimmed)
                        }
                    }
                }
                try? await Task.sleep(for: .seconds(self.liveTranscriptionInterval))
            }
        }
    }

    private func stopLiveTranscription() {
        liveTranscriptionTask?.cancel()
        liveTranscriptionTask = nil
    }

    // MARK: - Hotkey update (called from SettingsView)

    func updateHotkey(_ option: ModelManager.HotkeyOption) {
        ModelManager.selectedHotkeyID = option.id
        hotKeyMonitor.updateHotkey(keyCode: option.keyCode, modifiers: option.modifiers)
        print("[FieldWhisperer] Hotkey changed to \(option.label)")
    }

    // MARK: - Dock icon

    /// Clicking the Dock icon when no window is open shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { menuBarControllerDidRequestSettings(menuBarController) }
        return true
    }

    // MARK: - Permissions

    @discardableResult
    private func requestAccessibilityPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}

// MARK: - MenuBarControllerDelegate

extension AppDelegate: MenuBarControllerDelegate {
    func menuBarControllerDidRequestSettings(_ controller: MenuBarController) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                transcriptionEngine: transcriptionEngine,
                appDelegate: self
            )
            settingsWindowController?.window?.delegate = self
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func menuBarControllerDidRequestQuit(_ controller: MenuBarController) {
        NSApp.terminate(nil)
    }

    func menuBarControllerDidRequestRepaste(_ controller: MenuBarController, text: String) {
        // Capture frontmost app now (before menu closes and focus changes)
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Task {
            // Small delay so the menu has fully closed before we try to insert
            try? await Task.sleep(for: .milliseconds(200))
            let _ = textInserter.insert(text: text, targetPid: pid)
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        settingsWindowController = nil
    }
}
