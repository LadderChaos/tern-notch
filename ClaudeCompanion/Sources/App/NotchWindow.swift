import SwiftUI
import AppKit

/// Manages the floating panel window positioned at the MacBook notch.
/// Inspired by boringnotch's window positioning approach.
final class NotchWindowController {
    private var window: NSPanel?

    /// Create and show the notch-anchored floating panel
    func showWindow(with viewModel: CompanionViewModel) {
        guard window == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        // Panel configuration — float above everything, no shadow/chrome
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isOpaque = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        // Content view
        let hostingView = NSHostingView(rootView: CompanionNotchView(viewModel: viewModel))
        panel.contentView = hostingView

        // Position at center-top of screen (below notch)
        positionAtNotch(panel)

        panel.orderFrontRegardless()
        self.window = panel
    }

    func hideWindow() {
        window?.orderOut(nil)
        window = nil
    }

    /// Position the window just below the MacBook notch area
    private func positionAtNotch(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame

        // Calculate notch position (center-top of screen)
        let panelWidth: CGFloat = 400
        let x = screenFrame.midX - panelWidth / 2
        // Place just below the menu bar / notch area
        let menuBarHeight = screenFrame.height - visibleFrame.height - visibleFrame.origin.y
        let y = screenFrame.maxY - menuBarHeight - 10

        panel.setFrameTopLeftPoint(NSPoint(x: x, y: y))
    }
}
