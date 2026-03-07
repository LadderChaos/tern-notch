import SwiftUI
import AppKit

/// App delegate managing the menu bar item and notch window lifecycle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let windowController = NotchWindowController()
    private let viewModel = CompanionViewModel()
    private var isVisible = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — this is a menu bar / notch-only app
        NSApp.setActivationPolicy(.accessory)

        // Create menu bar status item
        setupStatusBar()

        // Show notch window
        windowController.showWindow(with: viewModel)

        // Start telemetry receiver
        viewModel.start()

        // Load demo data for first launch (remove for production)
        viewModel.loadDemoData()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stop()
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Claude Companion")
            button.action = #selector(toggleVisibility)
            button.target = self
        }

        // Context menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Companion", action: #selector(toggleVisibility), keyEquivalent: "t"))
        menu.addItem(NSMenuItem.separator())

        let demoItem = NSMenuItem(title: "Load Demo Data", action: #selector(loadDemo), keyEquivalent: "d")
        menu.addItem(demoItem)

        let resetItem = NSMenuItem(title: "Reset Session", action: #selector(resetSession), keyEquivalent: "r")
        menu.addItem(resetItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func toggleVisibility() {
        if isVisible {
            windowController.hideWindow()
        } else {
            windowController.showWindow(with: viewModel)
        }
        isVisible.toggle()
    }

    @objc private func loadDemo() {
        viewModel.loadDemoData()
    }

    @objc private func resetSession() {
        viewModel.stop()
        viewModel.start()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
