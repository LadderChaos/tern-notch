import AppKit
import SwiftUI

@main
struct TernNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// Geometry of the notch surface on the current screen.
struct NotchMetrics: Equatable {
    /// Camera housing width; 0 on displays without a notch (a faux notch is drawn over the menu bar).
    var cameraWidth: CGFloat = 0
    /// Camera housing (or menu bar) height. The collapsed silhouette is exactly this tall.
    var headerHeight: CGFloat = 32
    var collapsedWidth: CGFloat = 190
    var expandedSize = CGSize(width: 760, height: 440)
}

final class NotchModel: ObservableObject {
    @Published var expanded = false
    @Published var metrics = NotchMetrics()
    /// Horizontal shift of the silhouette from the window center, nonzero only when the window is clamped to a screen edge.
    @Published var centerOffset: CGFloat = 0
}

private enum NotchStyle {
    /// Width of each black wing beside the camera housing while collapsed.
    static let wing: CGFloat = 74
    /// Transparent window margin around the expanded silhouette for its drop shadow.
    static let margin: CGFloat = 30
    static let expandedWidth: CGFloat = 760
    static let expandedHeight: CGFloat = 440
    static let collapsedRadii = (top: CGFloat(6), bottom: CGFloat(10))
    static let expandedRadii = (top: CGFloat(14), bottom: CGFloat(28))
    static let contentInset: CGFloat = 30
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = TernStreamStore()
    private let model = NotchModel()
    private let viewState = TernViewState()
    private lazy var traffic = TernTraffic(store: store)
    private var panel: NotchPanel?
    private var statusItem: NSStatusItem?
    private var toggleMenuItem: NSMenuItem?
    private var pendingShrink: DispatchWorkItem?
    private var screenFrame = NSRect.zero
    private var notchCenterX: CGFloat = 0
    /// Requested state; `model.expanded` follows it one run-loop turn later when opening.
    private var wantsExpanded = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The silhouette draws its own shadow; a window shadow would outline the transparent frame.
        panel.hasShadow = false
        panel.level = .mainMenu + 3
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.onCancel = { [weak self] in self?.back() }

        let root = NotchRootView(
            store: store,
            traffic: traffic,
            model: model,
            viewState: viewState,
            toggle: { [weak self] in self?.toggle() },
            collapse: { [weak self] in self?.setExpanded(false) }
        )
        let hostingView = NotchHostingView(rootView: root)
        // The panel frame drives layout; SwiftUI must not resize the window to its ideal size.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        self.panel = panel

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Tern Notch")
        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: "Open Tern Notch", action: #selector(toggleFromMenu), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Tern Notch", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
        toggleMenuItem = toggleItem

        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        store.start()
        positionPanel()
        panel.orderFrontRegardless()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }

    /// Clicking anywhere outside the notch folds it back into the camera housing.
    func applicationDidResignActive(_ notification: Notification) {
        setExpanded(false)
    }

    @objc private func toggleFromMenu() { toggle() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    @objc private func screenParametersChanged() {
        positionPanel()
        panel?.orderFrontRegardless()
    }

    private func toggle() { setExpanded(!wantsExpanded) }

    /// Esc steps back from message to agent to overview, then collapses.
    private func back() {
        guard wantsExpanded else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var handled = false
        withAnimation(reduce ? nil : .easeInOut(duration: 0.18)) { handled = viewState.back() }
        if !handled { setExpanded(false) }
    }

    private func setExpanded(_ expanded: Bool) {
        guard wantsExpanded != expanded else { return }
        wantsExpanded = expanded
        toggleMenuItem?.title = expanded ? "Close Tern Notch" : "Open Tern Notch"
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        pendingShrink?.cancel()
        pendingShrink = nil
        if expanded {
            // Grow the transparent window first so the silhouette can unfold inside it without
            // shifting, then animate on the next turn after the resized layout has landed.
            applyFrame(large: true)
            NSApplication.shared.activate(ignoringOtherApps: true)
            panel?.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.wantsExpanded else { return }
                withAnimation(reduce ? .easeOut(duration: 0.12) : .spring(response: 0.42, dampingFraction: 0.84)) {
                    self.model.expanded = true
                }
            }
        } else {
            withAnimation(reduce ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.92)) {
                model.expanded = false
            }
            // Shrink the window back to the collapsed silhouette once the fold finishes, so the
            // transparent margin never blocks clicks on the menu bar.
            let task = DispatchWorkItem { [weak self] in
                guard let self = self, !self.wantsExpanded else { return }
                self.pendingShrink = nil
                self.applyFrame(large: false)
                self.panel?.orderFrontRegardless()
            }
            pendingShrink = task
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduce ? 0.15 : 0.5), execute: task)
        }
    }

    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first {
            $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func positionPanel() {
        guard panel != nil, let screen = notchScreen() else { return }
        let frame = screen.frame
        var cameraWidth: CGFloat = 0
        var centerX = frame.midX
        if screen.safeAreaInsets.top > 0,
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let left = frame.minX + leftArea.width
            let right = frame.maxX - rightArea.width
            if right > left {
                cameraWidth = right - left
                centerX = (left + right) / 2
            }
        }
        let menuBarHeight = frame.maxY - screen.visibleFrame.maxY
        let headerHeight = cameraWidth > 0 ? screen.safeAreaInsets.top : min(max(menuBarHeight, 24), 32)
        let collapsedWidth = cameraWidth > 0 ? cameraWidth + 2 * NotchStyle.wing : 190
        let width = max(collapsedWidth, min(NotchStyle.expandedWidth, frame.width - 2 * NotchStyle.margin))
        let available = frame.maxY - screen.visibleFrame.minY - NotchStyle.margin
        let height = max(headerHeight + 120, min(NotchStyle.expandedHeight, available))
        let metrics = NotchMetrics(
            cameraWidth: cameraWidth,
            headerHeight: headerHeight,
            collapsedWidth: collapsedWidth,
            expandedSize: CGSize(width: width, height: height)
        )
        if model.metrics != metrics { model.metrics = metrics }
        screenFrame = frame
        notchCenterX = centerX
        applyFrame(large: wantsExpanded || pendingShrink != nil)
    }

    /// The window's top edge is always the physical top of the screen, centered on the camera.
    private func applyFrame(large: Bool) {
        guard let panel else { return }
        let metrics = model.metrics
        let size = large
            ? CGSize(width: metrics.expandedSize.width + 2 * NotchStyle.margin, height: metrics.expandedSize.height + NotchStyle.margin)
            : CGSize(width: metrics.collapsedWidth, height: metrics.headerHeight)
        let x = min(max(notchCenterX - size.width / 2, screenFrame.minX), screenFrame.maxX - size.width)
        let offset = notchCenterX - (x + size.width / 2)
        if model.centerOffset != offset { model.centerOffset = offset }
        panel.setFrame(NSRect(x: x, y: screenFrame.maxY - size.height, width: size.width, height: size.height), display: true, animate: false)
    }
}

private final class NotchPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

private final class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// The first click on the notch acts immediately, even while another app is active.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Hardware-notch silhouette: flush with the screen top, flaring outward at the top corners and
/// rounded at the bottom, so the black surface reads as an extension of the camera housing.
struct NotchSilhouette: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = max(0, min(topRadius, rect.width / 4, rect.height / 2))
        let bottom = max(0, min(bottomRadius, (rect.width - 2 * top) / 2, rect.height - top))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top),
                          control: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.minX + top, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX - top, y: rect.maxY), radius: bottom)
        path.addArc(tangent1End: CGPoint(x: rect.maxX - top, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX - top, y: rect.minY), radius: bottom)
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct NotchRootView: View {
    @ObservedObject var store: TernStreamStore
    @ObservedObject var traffic: TernTraffic
    @ObservedObject var model: NotchModel
    let viewState: TernViewState
    let toggle: () -> Void
    let collapse: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let metrics = model.metrics
        let expanded = model.expanded
        let roster = TernRoster(store.agents)
        let radii = expanded ? NotchStyle.expandedRadii : NotchStyle.collapsedRadii
        let shape = NotchSilhouette(topRadius: radii.top, bottomRadius: radii.bottom)
        let size = expanded ? metrics.expandedSize : CGSize(width: metrics.collapsedWidth, height: metrics.headerHeight)
        VStack(spacing: 0) {
            header(metrics, roster, expanded: expanded)
            if expanded {
                // Fixed final size: the silhouette unfolds over already-laid-out content instead of reflowing it.
                TernView(store: store, traffic: traffic, state: viewState)
                    .frame(width: metrics.expandedSize.width - 2 * NotchStyle.contentInset,
                           height: max(0, metrics.expandedSize.height - metrics.headerHeight - 20),
                           alignment: .top)
                    .padding(.top, 4)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -12)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .background(
            shape.fill(Color.black)
                .shadow(color: Color.black.opacity(expanded ? 0.55 : 0), radius: 18, y: 10)
        )
        .contentShape(shape)
        .offset(x: model.centerOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Color.white)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func header(_ metrics: NotchMetrics, _ roster: TernRoster, expanded: Bool) -> some View {
        let gap = metrics.cameraWidth > 0 ? metrics.cameraWidth : 12
        let hues = roster.active.map { agentHue($0.pane) }
        if expanded {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    ActivityPulse(hues: hues, arrivals: traffic.arrivals)
                    Text("tern").font(.system(size: 13, weight: .bold, design: .rounded))
                    liveBadge
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                Color.clear.frame(width: gap)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text("\(roster.active.count) working · \(roster.idle.count) idle")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .lineLimit(1)
                    iconButton("arrow.clockwise", label: "Restart watcher") { store.restart() }
                    iconButton("chevron.up", label: "Collapse Tern Notch", action: collapse)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, NotchStyle.contentInset - 4)
            .frame(height: metrics.headerHeight)
            .contentShape(Rectangle())
            .onTapGesture(perform: collapse)
            .transition(.opacity)
        } else {
            Button(action: toggle) {
                HStack(spacing: 0) {
                    ActivityPulse(hues: hues, arrivals: traffic.arrivals)
                        .frame(maxWidth: .infinity)
                    Color.clear.frame(width: gap)
                    collapsedStatus(roster)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, NotchStyle.collapsedRadii.top + 2)
                .frame(height: metrics.headerHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Tern Notch")
            .accessibilityValue(status(roster))
            .help("Open Tern orchestration · \(status(roster))")
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func collapsedStatus(_ roster: TernRoster) -> some View {
        let fresh = traffic.pulses.count
        Group {
            if !store.isRunning || store.error != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange)
            } else if fresh > 0 && !reduceMotion {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 9.5, weight: .bold))
                    Text("+\(fresh)").font(.system(size: 11.5, weight: .bold, design: .rounded))
                }
                .foregroundStyle(traffic.pulses.contains(where: \.failed) ? Color.red : ternAccent)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(roster.active.count)")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(roster.active.isEmpty ? Color.white.opacity(0.5) : Color.white)
                    Text("/\(roster.openCount)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: fresh > 0)
    }

    private var liveBadge: some View {
        HStack(spacing: 4) {
            Circle().fill(store.isRunning ? Color.green : Color.orange).frame(width: 5, height: 5)
            Text(store.isRunning ? "live" : "offline")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(store.isRunning ? Color.green.opacity(0.85) : Color.orange)
        }
        .accessibilityElement(children: .combine)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func status(_ roster: TernRoster) -> String {
        if !store.isRunning { return "Watcher unavailable" }
        return "\(roster.active.count) working · \(roster.openCount) open agents"
    }
}
