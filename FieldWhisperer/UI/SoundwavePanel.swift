import AppKit
import SwiftUI

/// A borderless, always-on-top floating NSPanel that hosts the soundwave animation.
/// It never steals keyboard focus (.nonactivatingPanel) and follows the user across
/// Spaces (.canJoinAllSpaces).
///
/// Entry/exit animations are driven purely by SwiftUI (scale + offset + opacity spring),
/// so the NSPanel itself is always fully opaque — no NSAnimationContext needed.
final class SoundwavePanel: NSPanel {

    private let viewModel: SoundwaveViewModel

    /// Cancellable auto-hide work item (used by showCopied).
    private var pendingHide: DispatchWorkItem?

    init(viewModel: SoundwaveViewModel) {
        self.viewModel = viewModel

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 56),
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )

        level              = .floating
        backgroundColor    = .clear
        isOpaque           = false
        hasShadow          = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        alphaValue         = 1.0   // SwiftUI controls visual opacity via isVisible

        let content = NSHostingView(rootView: SoundwaveView(viewModel: viewModel))
        content.frame = NSRect(x: 0, y: 0, width: 320, height: 56)
        contentView = content
    }

    // MARK: - Show / update / hide

    func show() {
        pendingHide?.cancel()
        pendingHide = nil

        positionAtTopCenter()
        viewModel.state    = .recording
        viewModel.liveText = ""
        viewModel.isVisible = false   // start collapsed so the spring has somewhere to come from

        orderFront(nil)

        // Kick off entry on next runloop tick so SwiftUI renders the initial collapsed state first
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.62)) {
                self.viewModel.isVisible = true
            }
        }
    }

    func showTranscribing() {
        viewModel.state    = .transcribing
        viewModel.liveText = ""
    }

    func showCopied() {
        pendingHide?.cancel()

        viewModel.state    = .copied
        viewModel.liveText = ""
        // Panel is already visible — just update state then auto-hide after a beat
        let item = DispatchWorkItem { [weak self] in self?.hide() }
        pendingHide = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: item)
    }

    func updateLevel(_ level: Float) {
        viewModel.audioLevel = Double(level)
    }

    /// Update the live transcription text shown while recording.
    func updateLiveText(_ text: String) {
        viewModel.liveText = text
    }

    func hide() {
        pendingHide?.cancel()
        pendingHide = nil

        // Exit animation: spring back up and shrink — reverse of entry
        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
            viewModel.isVisible = false
        }

        // Remove the window after the spring has settled
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.orderOut(nil)
            MainActor.assumeIsolated {
                self?.viewModel.state     = .hidden
                self?.viewModel.liveText  = ""
                self?.viewModel.audioLevel = 0
            }
        }
    }

    // MARK: - Positioning

    private func positionAtTopCenter() {
        guard let screen = NSScreen.main else { return }
        let screenFrame  = screen.visibleFrame
        let panelWidth:  CGFloat = 320
        let panelHeight: CGFloat = 56
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - panelHeight - 8
        setFrameOrigin(NSPoint(x: x, y: y))
        setContentSize(NSSize(width: panelWidth, height: panelHeight))
    }
}
