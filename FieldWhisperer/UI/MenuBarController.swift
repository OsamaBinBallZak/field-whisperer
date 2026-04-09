import AppKit
import Combine

@MainActor
protocol MenuBarControllerDelegate: AnyObject {
    func menuBarControllerDidRequestSettings(_ controller: MenuBarController)
    func menuBarControllerDidRequestQuit(_ controller: MenuBarController)
}

/// Owns the NSStatusItem (menu bar icon) and rebuilds the menu whenever
/// the TranscriptionEngine's loading state changes.
@MainActor
final class MenuBarController: NSObject {

    private var statusItem: NSStatusItem!
    private let transcriptionEngine: TranscriptionEngine
    weak var delegate: MenuBarControllerDelegate?

    private var cancellables = Set<AnyCancellable>()
    private var isRecording = false

    init(transcriptionEngine: TranscriptionEngine, delegate: MenuBarControllerDelegate) {
        self.transcriptionEngine = transcriptionEngine
        self.delegate = delegate
        super.init()
        setupStatusItem()

        // Rebuild menu whenever the engine status changes
        transcriptionEngine.$loadingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateButtonImage(recording: false)
        rebuildMenu()
    }

    // MARK: - Menu

    func rebuildMenu() {
        let menu = NSMenu()

        // Header
        let header = NSMenuItem(title: "FieldWhisperer", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        // Engine status
        let status = NSMenuItem(title: transcriptionEngine.statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        // Usage hint
        if transcriptionEngine.isReady {
            let hint = NSMenuItem(title: "Hold ⌥Space → speak → release to paste",
                                  action: nil, keyEquivalent: "")
            hint.isEnabled = false
            hint.attributedTitle = NSAttributedString(
                string: "Hold ⌥Space → speak → release to paste",
                attributes: [.font: NSFont.systemFont(ofSize: 11),
                             .foregroundColor: NSColor.secondaryLabelColor])
            menu.addItem(hint)
        }

        menu.addItem(.separator())

        // Settings
        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettings),
                                      keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit FieldWhisperer",
                                  action: #selector(quit),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Recording indicator

    /// Briefly tints the menu bar icon orange to signal "not ready yet"
    func flashNotReady() {
        guard let button = statusItem.button else { return }
        button.contentTintColor = .systemOrange
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, !self.isRecording else { return }
            button.contentTintColor = nil
        }
    }

    func setRecordingIndicator(active: Bool) {
        isRecording = active
        updateButtonImage(recording: active)
    }

    private func updateButtonImage(recording: Bool) {
        guard let button = statusItem.button else { return }
        let symbolName = recording ? "mic.fill" : "mic.fill"
        let image = NSImage(systemSymbolName: symbolName,
                            accessibilityDescription: "FieldWhisperer")
        image?.isTemplate = !recording
        button.image = image
        button.contentTintColor = recording ? .systemRed : nil
    }

    // MARK: - Actions

    @objc private func openSettings() {
        delegate?.menuBarControllerDidRequestSettings(self)
    }

    @objc private func quit() {
        delegate?.menuBarControllerDidRequestQuit(self)
    }
}
