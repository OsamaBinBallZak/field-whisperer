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

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[FieldWhisperer] App launched.")

        // Prompt for Accessibility permission immediately on first launch
        let axTrusted = requestAccessibilityPermission()
        print("[FieldWhisperer] AXIsProcessTrusted = \(axTrusted)")
        if !axTrusted {
            print("[FieldWhisperer] ⚠️ Accessibility not trusted. " +
                  "Text insertion will use pasteboard fallback (Cmd+V). " +
                  "Grant in System Settings → Accessibility, then toggle OFF/ON and restart.")
        }

        // Initialize subsystems
        transcriptionEngine = TranscriptionEngine()
        audioRecorder = AudioRecorder()
        textInserter = TextInserter()

        let soundwaveViewModel = SoundwaveViewModel()
        soundwavePanel = SoundwavePanel(viewModel: soundwaveViewModel)

        menuBarController = MenuBarController(
            transcriptionEngine: transcriptionEngine,
            delegate: self
        )

        // Load Whisper model in the background; menu bar reflects loading state
        Task {
            await transcriptionEngine.loadModel(variant: ModelManager.selectedModel)
            menuBarController.rebuildMenu()
        }

        // Start monitoring for the FN key globally
        hotKeyMonitor = HotKeyMonitor(
            onFNDown: { [weak self] in await self?.beginRecording() },
            onFNUp:   { [weak self] in await self?.endRecording()   }
        )
        hotKeyMonitor.start()
    }

    // MARK: - Recording state machine

    private func beginRecording() async {
        guard state == .idle else {
            print("[FieldWhisperer] beginRecording: ignored — state is \(state), not idle")
            return
        }
        guard transcriptionEngine.isReady else {
            print("[FieldWhisperer] beginRecording: model not ready — \(transcriptionEngine.statusText)")
            menuBarController.flashNotReady()
            return
        }
        print("[FieldWhisperer] beginRecording: starting…")
        state = .recording
        soundwavePanel.show()
        menuBarController.setRecordingIndicator(active: true)
        audioRecorder.start { [weak self] level in
            self?.soundwavePanel.updateLevel(level)
        }
    }

    private func endRecording() async {
        guard state == .recording else {
            print("[FieldWhisperer] endRecording: ignored — state is \(state), not recording")
            return
        }
        state = .transcribing
        let samples = audioRecorder.stop()
        print("[FieldWhisperer] endRecording: captured \(samples.count) samples")
        soundwavePanel.showTranscribing()
        menuBarController.setRecordingIndicator(active: false)

        do {
            let text = try await transcriptionEngine.transcribe(audioSamples: samples)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                print("[FieldWhisperer] Inserting text: \"\(trimmed.prefix(80))\"")
                textInserter.insert(text: trimmed)
            } else {
                print("[FieldWhisperer] Transcription returned empty text — nothing to insert.")
            }
        } catch {
            print("[FieldWhisperer] ❌ Transcription error: \(error.localizedDescription)")
        }

        soundwavePanel.hide()
        state = .idle
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
            settingsWindowController = SettingsWindowController(transcriptionEngine: transcriptionEngine)
            settingsWindowController?.window?.delegate = self
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func menuBarControllerDidRequestQuit(_ controller: MenuBarController) {
        NSApp.terminate(nil)
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        settingsWindowController = nil
    }
}
