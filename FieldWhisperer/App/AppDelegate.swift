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
        // Prompt for Accessibility permission immediately on first launch
        requestAccessibilityPermission()

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
        guard state == .idle else { return }
        guard transcriptionEngine.isReady else {
            print("[FieldWhisperer] FN pressed but model not ready: \(transcriptionEngine.statusText)")
            menuBarController.flashNotReady()
            return
        }
        state = .recording
        soundwavePanel.show()
        menuBarController.setRecordingIndicator(active: true)
        audioRecorder.start { [weak self] level in
            self?.soundwavePanel.updateLevel(level)
        }
    }

    private func endRecording() async {
        guard state == .recording else { return }
        state = .transcribing
        let samples = audioRecorder.stop()
        soundwavePanel.showTranscribing()
        menuBarController.setRecordingIndicator(active: false)

        do {
            let text = try await transcriptionEngine.transcribe(audioSamples: samples)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                textInserter.insert(text: trimmed)
            }
        } catch {
            print("[FieldWhisperer] Transcription error: \(error.localizedDescription)")
        }

        soundwavePanel.hide()
        state = .idle
    }

    // MARK: - Permissions

    private func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
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
