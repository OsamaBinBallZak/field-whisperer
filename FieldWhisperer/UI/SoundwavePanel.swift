import AppKit
import SwiftUI

/// A borderless, always-on-top floating NSPanel that hosts the soundwave animation.
/// It never steals keyboard focus (.nonactivatingPanel) and follows the user across
/// Spaces (.canJoinAllSpaces).
final class SoundwavePanel: NSPanel {

    private let viewModel: SoundwaveViewModel

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
        alphaValue         = 0

        let content = NSHostingView(rootView: SoundwaveView(viewModel: viewModel))
        content.frame = NSRect(x: 0, y: 0, width: 320, height: 56)
        contentView = content
    }

    // MARK: - Show / update / hide

    func show() {
        positionAtTopCenter()
        viewModel.state    = .recording
        viewModel.liveText = ""
        if !isVisible { orderFront(nil) }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            self.animator().alphaValue = 1.0
        }
    }

    func showTranscribing() {
        viewModel.state    = .transcribing
        viewModel.liveText = ""
    }

    func showCopied() {
        viewModel.state    = .copied
        viewModel.liveText = ""
        positionAtTopCenter()
        if !isVisible { orderFront(nil) }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            self.animator().alphaValue = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.hide()
        }
    }

    func updateLevel(_ level: Float) {
        viewModel.audioLevel = Double(level)
    }

    /// Update the live transcription text shown while recording.
    func updateLiveText(_ text: String) {
        viewModel.liveText = text
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            MainActor.assumeIsolated {
                self.viewModel.state    = .hidden
                self.viewModel.liveText = ""
                self.viewModel.audioLevel = 0
            }
        })
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
