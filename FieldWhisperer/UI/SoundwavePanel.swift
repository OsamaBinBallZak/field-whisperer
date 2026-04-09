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
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 64),
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )

        level             = .floating
        backgroundColor   = .clear
        isOpaque          = false
        hasShadow         = false          // shadow is drawn by SwiftUI material
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        alphaValue        = 0

        let content = NSHostingView(rootView: SoundwaveView(viewModel: viewModel))
        content.frame = NSRect(x: 0, y: 0, width: 280, height: 64)
        contentView = content
    }

    // MARK: - Show / update / hide

    func show() {
        positionAtTopCenter()
        viewModel.state = .recording
        if !isVisible { orderFront(nil) }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            self.animator().alphaValue = 1.0
        }
    }

    func showTranscribing() {
        viewModel.state = .transcribing
    }

    func updateLevel(_ level: Float) {
        viewModel.audioLevel = Double(level)
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.viewModel.state = .hidden
            self.viewModel.audioLevel = 0
        })
    }

    // MARK: - Positioning

    private func positionAtTopCenter() {
        guard let screen = NSScreen.main else { return }
        let screenFrame  = screen.visibleFrame
        let panelWidth:  CGFloat = 280
        let panelHeight: CGFloat = 64
        // Place just below the macOS menu bar (visibleFrame already excludes it)
        let x = screenFrame.midX - panelWidth  / 2
        let y = screenFrame.maxY - panelHeight - 8
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
