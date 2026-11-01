import AppKit
import Combine
import SwiftUI

let ternAccent = Color(red: 0.36, green: 0.86, blue: 0.92)

private let agentPalette: [Color] = [
    Color(red: 0.36, green: 0.86, blue: 0.92),
    Color(red: 0.99, green: 0.63, blue: 0.31),
    Color(red: 0.71, green: 0.57, blue: 1.00),
    Color(red: 0.43, green: 0.91, blue: 0.57),
    Color(red: 1.00, green: 0.46, blue: 0.62),
    Color(red: 0.98, green: 0.86, blue: 0.37),
    Color(red: 0.43, green: 0.63, blue: 1.00),
    Color(red: 0.95, green: 0.52, blue: 0.95),
]

/// Stable identity color shared by an agent's rail dot, message chips, and flow packets.
func agentHue(_ pane: UInt64) -> Color {
    agentPalette[Int(pane % UInt64(agentPalette.count))]
}

// MARK: - Roster

/// Working agents (or orchestrators waiting on running subagents) first, then idle, then closed.
/// Order inside each group is stable so rows do not shuffle on every snapshot.
struct TernRoster {
    let active: [TernAgent]
    let idle: [TernAgent]
    let openCount: Int
    private let byPane: [UInt64: TernAgent]

    init(_ agents: [TernAgent]) {
        let stable: (TernAgent, TernAgent) -> Bool = { $0.tab == $1.tab ? $0.pane < $1.pane : $0.tab < $1.tab }
        let isActive: (TernAgent) -> Bool = { $0.open && ($0.working || $0.subagents.contains(where: \.running)) }
        active = agents.filter(isActive).sorted(by: stable)
        idle = agents.filter { $0.open && !isActive($0) }.sorted(by: stable) + agents.filter { !$0.open }.sorted(by: stable)
        openCount = agents.filter(\.open).count
        byPane = Dictionary(agents.map { ($0.pane, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func agent(_ pane: UInt64) -> TernAgent? { byPane[pane] }
}

// MARK: - Traffic

/// Owns message identity and fresh-arrival detection for both notch states, so opening the notch
/// never replays loaded history and delivery updates keep their identity instead of reading as new traffic.
final class TernTraffic: ObservableObject {
    static let pulseDuration: TimeInterval = 1.4

    /// Oldest to newest.
    @Published private(set) var entries: [TrafficEntry] = []
    /// Newly observed messages, alive for `pulseDuration`.
    @Published private(set) var pulses: [TrafficPulse] = []
    /// Increments only when fresh traffic arrives; drives insertion animation.
    @Published private(set) var arrivals = 0

    private var observed: Set<TrafficEntry.ID> = []
    private var hasBaseline = false
    private var observingSince = Date()
    private var expiry: DispatchWorkItem?
    private var subscriptions: Set<AnyCancellable> = []

    init(store: TernStreamStore) {
        store.$messages
            .sink { [weak self, weak store] messages in
                self?.rebuild(messages, hasAgents: !(store?.agents.isEmpty ?? true))
            }
            .store(in: &subscriptions)
        store.$isRunning
            .removeDuplicates()
            .sink { [weak self] running in
                if !running { self?.resetBaseline() }
            }
            .store(in: &subscriptions)
    }

    func isFresh(_ id: TrafficEntry.ID) -> Bool { pulses.contains { $0.entry == id } }

    private func resetBaseline() {
        hasBaseline = false
        observingSince = Date()
        observed.removeAll(keepingCapacity: true)
        expiry?.cancel()
        expiry = nil
        if !pulses.isEmpty { pulses.removeAll() }
    }

    private func rebuild(_ messages: [TernMessage], hasAgents: Bool) {
        let now = Date()
        var occurrences: [TrafficKey: Int] = [:]
        let next = messages.enumerated().map { offset, item in
            let key = TrafficKey(item)
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            return TrafficEntry(id: .init(key: key, occurrence: occurrence), item: item, offset: offset)
        }.sorted {
            let left = $0.item.sentMs ?? $0.item.deliveredMs ?? Int64.min
            let right = $1.item.sentMs ?? $1.item.deliveredMs ?? Int64.min
            return left == right ? $0.offset < $1.offset : left < right
        }
        var fresh: [TrafficEntry] = []
        if hasBaseline {
            let nowMs = now.timeIntervalSince1970 * 1000
            let earliest = max(observingSince.timeIntervalSince1970 * 1000, nowMs - 5000)
            fresh = next.filter { entry in
                guard !observed.contains(entry.id), let sent = entry.item.sentMs else { return false }
                return Double(sent) >= earliest && Double(sent) <= nowMs + 1000
            }
        } else if !messages.isEmpty || hasAgents {
            // Suppress loaded history, including the first snapshot after reconnect.
            hasBaseline = true
            observingSince = now
        }
        // Retain recently seen identities across transient snapshot omissions.
        let recentCutoff = Int64((now.timeIntervalSince1970 - 6) * 1000)
        observed = Set(next.map(\.id)).union(observed.filter { ($0.key.sent ?? Int64.min) >= recentCutoff })
        if Self.changed(entries, next) { entries = next }
        guard !fresh.isEmpty else { return }
        let live = pulses.filter { now.timeIntervalSince($0.started) < Self.pulseDuration }
        let added = fresh.suffix(12).map {
            TrafficPulse(entry: $0.id, from: $0.item.from.pane, fromSubagent: Self.subagent($0.item.from),
                         to: $0.item.to.pane, toSubagent: Self.subagent($0.item.to), failed: $0.item.failed, started: now)
        }
        pulses = Array((live + added).suffix(16))
        arrivals += fresh.count
        scheduleExpiry()
    }

    private static func subagent(_ node: TernNode) -> String? {
        node.subagent.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func changed(_ old: [TrafficEntry], _ new: [TrafficEntry]) -> Bool {
        guard old.count == new.count else { return true }
        return zip(old, new).contains { left, right in
            left.id != right.id || left.item.deliveredMs != right.item.deliveredMs || left.item.failed != right.item.failed
                || left.item.outcome != right.item.outcome || left.item.replied != right.item.replied
        }
    }

    private func scheduleExpiry() {
        expiry?.cancel()
        guard let oldest = pulses.map(\.started).min() else { expiry = nil; return }
        let delay = max(0.05, Self.pulseDuration - Date().timeIntervalSince(oldest))
        let task = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let now = Date()
            self.pulses.removeAll { now.timeIntervalSince($0.started) >= Self.pulseDuration }
            self.scheduleExpiry()
        }
        expiry = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }
}

/// Selection and draft survive collapsing the notch.
final class TernViewState: ObservableObject {
    @Published var selectedPane: UInt64?
    @Published var selectedMessage: TrafficEntry.ID?
    @Published var draft = ""
    @Published var showIdle = false

    /// Steps back one level; returns false when already at the overview.
    @discardableResult
    func back() -> Bool {
        if selectedMessage != nil { selectedMessage = nil; return true }
        if selectedPane != nil { selectedPane = nil; return true }
        return false
    }
}

// MARK: - Expanded notch body

struct TernView: View {
    @ObservedObject var store: TernStreamStore
    @ObservedObject var traffic: TernTraffic
    @ObservedObject var state: TernViewState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied: String?

    private let flowGutter: CGFloat = 14

    var body: some View {
        let roster = TernRoster(store.agents)
        VStack(alignment: .leading, spacing: 8) {
            if let error = store.error { banner("Watcher", error, offerRestart: true) }
            if let error = store.actionError { banner("Action failed", error, offerRestart: false) }
            HStack(alignment: .top, spacing: 12) {
                agentRail(roster).frame(width: 248)
                Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
                detail(roster)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(traffic.$entries) { entries in
            if let id = state.selectedMessage, !entries.contains(where: { $0.id == id }) { state.selectedMessage = nil }
        }
        .onChange(of: store.agents.map(\.pane)) { _, panes in
            if let pane = state.selectedPane, !panes.contains(pane) { state.selectedPane = nil }
        }
        .task(id: copied) {
            guard copied != nil else { return }
            try? await Task.sleep(for: .seconds(1.4))
            if !Task.isCancelled { copied = nil }
        }
    }

    // MARK: Agent rail

    private func agentRail(_ roster: TernRoster) -> some View {
        let idleVisible = state.showIdle || roster.active.isEmpty
        let hiddenIdle: Set<UInt64> = idleVisible ? [] : Set(roster.idle.map(\.pane))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                sectionLabel("Working")
                countBadge(roster.active.count, color: roster.active.isEmpty ? Color.white.opacity(0.4) : Color.green)
                Spacer(minLength: 0)
            }
            .padding(.leading, flowGutter + 8)
            if store.agents.isEmpty {
                railEmptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if roster.active.isEmpty {
                            Text("No agent is working right now.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.45))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                        }
                        ForEach(roster.active) { activeRow($0) }
                        if !roster.idle.isEmpty {
                            idleHeader(roster, visible: idleVisible).padding(.top, roster.active.isEmpty ? 0 : 6)
                            if idleVisible {
                                ForEach(roster.idle) { idleRow($0) }
                            }
                        }
                    }
                    .padding(.leading, flowGutter)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
                .overlayPreferenceValue(FlowAnchorsKey.self) { anchors in
                    FlowOverlay(anchors: anchors, working: roster.active.map(\.pane), pulses: traffic.pulses,
                                hiddenIdle: hiddenIdle, reduceMotion: reduceMotion)
                }
            }
        }
    }

    private var railEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: store.isRunning ? "dot.radiowaves.left.and.right" : "bolt.horizontal.circle")
                .font(.system(size: 20)).foregroundStyle(ternAccent)
            Text(store.isRunning ? "Waiting for agents" : "Watcher offline")
                .font(.system(size: 12.5, weight: .semibold))
            Text(store.isRunning ? "Working agents appear here first." : "Tern Notch retries every 5 seconds.")
                .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)
            if !store.isRunning {
                Button("Restart watcher") { store.restart() }.controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activeRow(_ agent: TernAgent) -> some View {
        let hue = agentHue(agent.pane)
        let selected = state.selectedPane == agent.pane
        let progress = agent.todo.flatMap { $0.total > 0 ? Double($0.done) / Double($0.total) : nil }
        return Button { select(agent.pane) } label: {
            HStack(alignment: .top, spacing: 9) {
                Circle().fill(hue).frame(width: 9, height: 9)
                    .shadow(color: hue.opacity(0.8), radius: 4)
                    .anchorPreference(key: FlowAnchorsKey.self, value: .center) { [FlowNode.pane(agent.pane): $0] }
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(agentName(agent))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let todo = agent.todo, todo.total > 0 {
                            Text("\(todo.done)/\(todo.total)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                    }
                    Text(activityLine(agent))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .lineLimit(1)
                    if let progress = progress {
                        ProgressTrack(fraction: progress, color: hue).frame(height: 3).padding(.top, 2)
                    }
                    if !agent.subagents.isEmpty { subagentStrip(agent.subagents, pane: agent.pane, hue: hue) }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(rowBackground(selected: selected, hue: hue, base: 0.05))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(agentName(agent)) · pane \(agent.pane) · tab \(agent.tab)\n\(agent.description)\n\(agent.cwd)")
        .accessibilityLabel("\(agentName(agent)), \(agentStatus(agent)), \(activityLine(agent))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func idleHeader(_ roster: TernRoster, visible: Bool) -> some View {
        let toggleable = !roster.active.isEmpty
        return Button {
            guard toggleable else { return }
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { state.showIdle.toggle() }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .rotationEffect(.degrees(visible ? 90 : 0))
                    .opacity(toggleable ? 1 : 0)
                    .frame(width: 9, height: 9)
                    .anchorPreference(key: FlowAnchorsKey.self, value: .center) { [FlowNode.idleGroup: $0] }
                sectionLabel("Idle")
                countBadge(roster.idle.count, color: Color.white.opacity(0.45))
                Spacer(minLength: 4)
                if !visible {
                    HStack(spacing: 3) {
                        ForEach(roster.idle.prefix(10)) { agent in
                            Circle().fill(agentHue(agent.pane).opacity(agent.open ? 0.75 : 0.25)).frame(width: 5, height: 5)
                        }
                    }
                }
            }
            .foregroundStyle(Color.white.opacity(0.55))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!toggleable)
        .help(visible ? "Hide idle agents" : "Show \(roster.idle.count) idle agents")
        .accessibilityLabel(visible ? "Hide idle agents" : "Show \(roster.idle.count) idle agents")
    }

    private func idleRow(_ agent: TernAgent) -> some View {
        let hue = agentHue(agent.pane)
        let selected = state.selectedPane == agent.pane
        return Button { select(agent.pane) } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(agent.open ? hue.opacity(0.7) : Color.clear)
                    .overlay(Circle().strokeBorder(hue.opacity(agent.open ? 0 : 0.5), lineWidth: 1))
                    .frame(width: 7, height: 7)
                    .frame(width: 9, height: 9)
                    .anchorPreference(key: FlowAnchorsKey.self, value: .center) { [FlowNode.pane(agent.pane): $0] }
                Text(agentName(agent))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(agent.open ? 0.8 : 0.42))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(agent.open ? quietLabel(agent.quietMs) : "closed")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.36))
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(rowBackground(selected: selected, hue: hue, base: 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(agentName(agent)) · pane \(agent.pane) · \(agentStatus(agent))\n\(agent.cwd)")
        .accessibilityLabel("\(agentName(agent)), \(agentStatus(agent))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func subagentStrip(_ subagents: [TernSubagent], pane: UInt64, hue: Color) -> some View {
        let running = subagents.filter(\.running).count
        return HStack(spacing: 4) {
            ForEach(Array(subagents.prefix(8).enumerated()), id: \.offset) { _, subagent in
                subagentDot(subagent, hue: hue)
                    .anchorPreference(key: FlowAnchorsKey.self, value: .center) { [FlowNode.subagent(pane, subagent.name): $0] }
            }
            Text(running > 0 ? "\(running)/\(subagents.count) sub" : "\(subagents.count) sub")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.42))
        }
        .padding(.top, 1)
    }

    private func subagentDot(_ subagent: TernSubagent, hue: Color) -> some View {
        Circle()
            .fill(subagent.running ? hue : subagent.done ? hue.opacity(0.3) : Color.clear)
            .overlay(Circle().strokeBorder(hue.opacity(subagent.running || subagent.done ? 0 : 0.5), lineWidth: 1))
            .frame(width: 5, height: 5)
    }

    // MARK: Detail pane

    private func detail(_ roster: TernRoster) -> some View {
        let entry = state.selectedMessage.flatMap { id in traffic.entries.first { $0.id == id } }
        let agent = state.selectedPane.flatMap { roster.agent($0) }
        let mode: DetailMode = entry.map { DetailMode.message($0.id) } ?? agent.map { DetailMode.agent($0.pane) } ?? .exchanges
        return ZStack(alignment: .topLeading) {
            Group {
                if let entry = entry {
                    messageDetail(entry, roster)
                } else if let agent = agent {
                    agentDetail(agent, roster)
                } else {
                    exchangesPanel(roster)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id(mode)
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: mode)
    }

    private func exchangesPanel(_ roster: TernRoster) -> some View {
        let failed = traffic.entries.suffix(80).filter(\.item.failed).count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                sectionLabel("Orchestration")
                countBadge(traffic.entries.count, color: ternAccent)
                if failed > 0 {
                    Text("\(failed) failed")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.9))
                }
                Spacer(minLength: 0)
                Text("newest first")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            exchangeList(traffic.entries, roster,
                         empty: store.isRunning ? "No orchestration messages yet." : "Messages appear when the watcher reconnects.")
        }
    }

    private func agentDetail(_ agent: TernAgent, _ roster: TernRoster) -> some View {
        let hue = agentHue(agent.pane)
        let related = traffic.entries.filter { $0.item.from.pane == agent.pane || $0.item.to.pane == agent.pane }
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                backButton
                Circle().fill(hue).frame(width: 10, height: 10).shadow(color: hue.opacity(0.8), radius: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(agentName(agent)).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(agentHeadline(agent))
                        .font(.system(size: 11))
                        .foregroundStyle(agent.open && agent.working ? Color.green.opacity(0.85) : Color.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Button { store.focus(agent.pane) } label: { Label("Focus", systemImage: "scope") }
                    .disabled(!agent.open)
                    .help("Focus pane \(agent.pane) in Tern")
                Button { copy(String(agent.pane), token: "pane") } label: {
                    Image(systemName: copied == "pane" ? "checkmark" : "doc.on.doc")
                }
                .help("Copy pane ID \(agent.pane)")
                .accessibilityLabel("Copy pane ID")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if !agent.description.isEmpty {
                Text(agent.description)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            if agent.tool != nil || agent.todo != nil { activityCard(agent, hue: hue) }
            if !agent.subagents.isEmpty { subagentChips(agent.subagents, hue: hue) }
            Text(locationLine(agent))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.42))
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)
                .help(agent.cwd)
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            HStack(spacing: 6) {
                sectionLabel("Exchanges")
                countBadge(related.count, color: hue)
                Spacer(minLength: 0)
            }
            exchangeList(related, roster, empty: "No exchanges with \(agentName(agent)) yet.")
            composer(agent, hue: hue)
        }
    }

    private func activityCard(_ agent: TernAgent, hue: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 1).fill(hue).frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                if let tool = agent.tool {
                    Text(tool.name.isEmpty ? "tool" : tool.name)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(hue)
                    if !tool.intent.isEmpty {
                        Text(tool.intent)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.white.opacity(0.8))
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
                if let todo = agent.todo, todo.total > 0 {
                    HStack(spacing: 8) {
                        ProgressTrack(fraction: Double(todo.done) / Double(todo.total), color: hue).frame(height: 4)
                        Text("\(todo.done)/\(todo.total) tasks")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .fixedSize()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func subagentChips(_ subagents: [TernSubagent], hue: Color) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                ForEach(Array(subagents.enumerated()), id: \.offset) { _, subagent in
                    HStack(spacing: 4) {
                        subagentDot(subagent, hue: hue)
                        Text(subagent.name).lineLimit(1)
                        Text(subagent.running ? "running" : subagent.done ? "done" : "idle")
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    .font(.system(size: 10.5))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func messageDetail(_ entry: TrafficEntry, _ roster: TernRoster) -> some View {
        let item = entry.item
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                backButton
                nodeChip(item.from, roster)
                Image(systemName: item.reply ? "arrowshape.turn.up.left.fill" : "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.4))
                nodeChip(item.to, roster)
                Spacer(minLength: 6)
                Button { copy(item.text, token: "message") } label: {
                    Label(copied == "message" ? "Copied" : "Copy", systemImage: copied == "message" ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy full message")
            }
            HStack(spacing: 8) {
                Text(entry.time)
                Text(item.kind)
                if item.reply { Text("reply") }
                if item.replied { Text("replied") }
                Text(delivery(item)).foregroundStyle(deliveryColor(item))
                Spacer(minLength: 4)
                Text("pane \(item.from.pane) → \(item.to.pane)")
                    .foregroundStyle(Color.white.opacity(0.32))
                    .textSelection(.enabled)
            }
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.5))
            .lineLimit(1)
            ScrollView {
                Text(item.text.isEmpty ? "(Empty message)" : item.text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
            HStack(spacing: 6) {
                jumpButton(item.from.pane, roster, role: "sender")
                if item.to.pane != item.from.pane { jumpButton(item.to.pane, roster, role: "recipient") }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func jumpButton(_ pane: UInt64, _ roster: TernRoster, role: String) -> some View {
        if let agent = roster.agent(pane) {
            Button {
                state.selectedMessage = nil
                state.selectedPane = pane
            } label: {
                Label(agentName(agent), systemImage: "arrow.up.forward.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(agentHue(pane))
            .help("Open \(role) \(agentName(agent))")
        }
    }

    // MARK: Exchanges

    private func exchangeList(_ entries: [TrafficEntry], _ roster: TernRoster, empty: String) -> some View {
        let recent = Array(entries.suffix(80).reversed())
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 5) {
                if recent.isEmpty {
                    Text(empty)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(recent) { entry in
                    exchangeRow(entry, roster)
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                }
            }
            // Only fresh arrivals animate; loaded history and delivery updates do not change `arrivals`.
            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.78), value: traffic.arrivals)
        }
        .scrollIndicators(.never)
        .frame(maxHeight: .infinity)
    }

    private func exchangeRow(_ entry: TrafficEntry, _ roster: TernRoster) -> some View {
        let item = entry.item
        let fresh = !reduceMotion && traffic.isFresh(entry.id)
        let color = item.failed ? Color.red : nodeHue(item.from, roster)
        let selected = state.selectedMessage == entry.id
        return Button { state.selectedMessage = entry.id } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    nodeChip(item.from, roster)
                    Image(systemName: item.reply ? "arrowshape.turn.up.left.fill" : "arrow.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.4))
                    nodeChip(item.to, roster)
                    Spacer(minLength: 6)
                    deliveryGlyph(item)
                    Text(entry.time)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.36))
                }
                Text(entry.preview)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fresh ? color.opacity(0.17) : Color.white.opacity(selected ? 0.1 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(color.opacity(fresh ? 0.75 : 0), lineWidth: 1)
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.9), value: fresh)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(route(item, roster)) · \(delivery(item))\n\(entry.preview)")
        .accessibilityLabel("\(entry.time), \(route(item, roster)), \(delivery(item)), \(entry.preview)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func nodeChip(_ node: TernNode, _ roster: TernRoster) -> some View {
        let hue = nodeHue(node, roster)
        return HStack(spacing: 4) {
            Circle().fill(hue).frame(width: 6, height: 6)
            Text(paneName(node.pane, roster))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(hue)
                .lineLimit(1)
            if let subagent = node.subagent, !subagent.isEmpty {
                Text(subagent)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }

    private func deliveryGlyph(_ item: TernMessage) -> some View {
        let symbol: String
        if item.failed { symbol = "exclamationmark.triangle.fill" }
        else if item.deliveredMs != nil { symbol = "checkmark" }
        else if item.deliveryObservable { symbol = "clock" }
        else { symbol = "questionmark.circle" }
        return Image(systemName: symbol)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(deliveryColor(item))
            .help(delivery(item))
            .accessibilityLabel(delivery(item))
    }

    // MARK: Controls

    private func composer(_ agent: TernAgent, hue: Color) -> some View {
        let canSend = agent.open && !state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 7) {
            TextField(agent.open ? "Message \(agentName(agent))…" : "Pane is closed", text: $state.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
                .disabled(!agent.open)
                .onSubmit { send(to: agent) }
                .accessibilityLabel("Message \(agentName(agent))")
            Button { send(to: agent) } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(canSend ? Color.black : Color.white.opacity(0.4))
                    .frame(width: 32, height: 28)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(canSend ? hue : Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help("Send to pane \(agent.pane)")
            .accessibilityLabel("Send to \(agentName(agent))")
        }
    }

    private var backButton: some View {
        Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { _ = state.back() } } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help("Back (Esc)")
        .accessibilityLabel("Back")
    }

    private func banner(_ title: String, _ text: String, offerRestart: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.orange)
                ScrollView {
                    Text(text)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 32)
            }
            Button { copy(text, token: title) } label: {
                Image(systemName: copied == title ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.plain)
            .help("Copy error")
            .accessibilityLabel("Copy \(title) error")
            if offerRestart {
                Button("Restart") { store.restart() }
                    .controlSize(.small)
                    .help("Restart ternwatch")
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.1)))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(Color.white.opacity(0.45))
    }

    private func countBadge(_ count: Int, color: Color) -> some View {
        Text("\(count)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    private func rowBackground(selected: Bool, hue: Color, base: Double) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(selected ? hue.opacity(0.18) : Color.white.opacity(base))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? hue.opacity(0.55) : Color.clear, lineWidth: 1)
            )
    }

    // MARK: Helpers

    private func select(_ pane: UInt64) {
        state.selectedMessage = nil
        if state.selectedPane != pane { state.draft = "" }
        state.selectedPane = state.selectedPane == pane ? nil : pane
    }

    private func send(to agent: TernAgent) {
        let text = state.draft
        guard agent.open, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.send(agent.pane, message: text)
        state.draft = ""
    }

    private func copy(_ text: String, token: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = token
    }

    private func paneName(_ pane: UInt64, _ roster: TernRoster) -> String {
        roster.agent(pane).map(agentName) ?? "External"
    }

    private func nodeHue(_ node: TernNode, _ roster: TernRoster) -> Color {
        roster.agent(node.pane) == nil ? Color.white.opacity(0.55) : agentHue(node.pane)
    }

    private func route(_ item: TernMessage, _ roster: TernRoster) -> String {
        "\(nodeName(item.from, roster)) → \(nodeName(item.to, roster))"
    }

    private func nodeName(_ node: TernNode, _ roster: TernRoster) -> String {
        let name = paneName(node.pane, roster)
        return node.subagent.flatMap { $0.isEmpty ? nil : "\(name)/\($0)" } ?? name
    }
}

private enum DetailMode: Hashable {
    case exchanges
    case agent(UInt64)
    case message(TrafficEntry.ID)
}

// MARK: - Activity animation

/// Compact equalizer for the notch wings: one bar per working agent in its identity color,
/// spiking when fresh traffic arrives. The timeline pauses whenever nothing is happening.
struct ActivityPulse: View {
    let hues: [Color]
    let arrivals: Int
    var height: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burstStart: Date?

    var body: some View {
        let bars = Array(hues.prefix(5))
        let live = !reduceMotion && (!bars.isEmpty || burstStart != nil)
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !live)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let burst = burstStart.map { max(0, 1 - timeline.date.timeIntervalSince($0) / 1.2) } ?? 0
                let colors = bars.isEmpty ? Array(repeating: ternAccent, count: 3) : bars
                for (index, color) in colors.enumerated() {
                    let level: Double
                    if bars.isEmpty {
                        level = 0.2 + 0.7 * burst * (0.6 + 0.4 * sin(t * 9 + Double(index) * 1.4))
                    } else if reduceMotion {
                        level = 0.55
                    } else {
                        let wave = 0.5 + 0.5 * sin(t * (4.2 + Double(index) * 1.1) + Double(index) * 1.9)
                        level = min(1, 0.25 + 0.6 * wave + 0.45 * burst)
                    }
                    let barHeight = max(3, size.height * level)
                    let rect = CGRect(x: CGFloat(index) * 5.5, y: (size.height - barHeight) / 2, width: 3, height: barHeight)
                    let opacity = bars.isEmpty ? 0.35 + 0.65 * burst : 1
                    context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color.opacity(opacity)))
                }
            }
        }
        .frame(width: CGFloat(max(bars.count, 3)) * 5.5 - 2.5, height: height)
        .onChange(of: arrivals) { _, _ in
            if !reduceMotion { burstStart = Date() }
        }
        .task(id: burstStart) {
            guard burstStart != nil else { return }
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { burstStart = nil }
        }
        .accessibilityHidden(true)
    }
}

private enum FlowNode: Hashable {
    case pane(UInt64)
    case subagent(UInt64, String)
    case idleGroup
}

private struct FlowAnchorsKey: PreferenceKey {
    static let defaultValue: [FlowNode: Anchor<CGPoint>] = [:]
    static func reduce(value: inout [FlowNode: Anchor<CGPoint>], nextValue: () -> [FlowNode: Anchor<CGPoint>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Draws working halos around active agent dots and fresh messages as comets arcing through the
/// rail gutter from sender to recipient, ending in an arrival ripple. Endpoints naming a subagent
/// resolve to that subagent's strip dot when visible; traffic that still lands on one point (parent
/// and an unlisted subagent sharing a pane) loops out of the halo and back. Renders nothing (and runs
/// no timeline) when no agent is working, no fresh traffic exists, or Reduce Motion is on.
private struct FlowOverlay: View {
    let anchors: [FlowNode: Anchor<CGPoint>]
    let working: [UInt64]
    let pulses: [TrafficPulse]
    let hiddenIdle: Set<UInt64>
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            if !reduceMotion && (!working.isEmpty || !pulses.isEmpty) {
                let points = anchors.mapValues { proxy[$0] }
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    Canvas { context, _ in
                        let now = timeline.date
                        for pane in working {
                            if let point = points[.pane(pane)] { drawHalo(&context, at: point, pane: pane, time: now.timeIntervalSinceReferenceDate) }
                        }
                        for pulse in pulses {
                            let progress = now.timeIntervalSince(pulse.started) / TernTraffic.pulseDuration
                            guard progress >= 0, progress < 1,
                                  let start = point(pulse.from, pulse.fromSubagent, points),
                                  let end = point(pulse.to, pulse.toSubagent, points) else { continue }
                            drawPulse(&context, pulse: pulse, from: start, to: end, progress: progress)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func point(_ pane: UInt64, _ subagent: String?, _ points: [FlowNode: CGPoint]) -> CGPoint? {
        if let subagent = subagent, let dot = points[.subagent(pane, subagent)] { return dot }
        return points[.pane(pane)] ?? (hiddenIdle.contains(pane) ? points[.idleGroup] : nil)
    }

    private func drawHalo(_ context: inout GraphicsContext, at point: CGPoint, pane: UInt64, time: TimeInterval) {
        let hue = agentHue(pane)
        for ring in 0..<2 {
            let phase = (time * 0.7 + Double(ring) * 0.5 + Double(pane % 7) * 0.13).truncatingRemainder(dividingBy: 1)
            let radius = 5 + 8 * phase
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(hue.opacity(0.55 * (1 - phase))), lineWidth: 1.2)
        }
    }

    private func drawPulse(_ context: inout GraphicsContext, pulse: TrafficPulse, from start: CGPoint, to end: CGPoint, progress: Double) {
        let color = pulse.failed ? Color.red : agentHue(pulse.from)
        var arc = Path()
        arc.move(to: start)
        if abs(start.y - end.y) < 2 && abs(start.x - end.x) < 2 {
            // Same-pane exchange with no distinct subagent anchor: a loop out into the row and back,
            // clockwise toward a subagent and counter-clockwise for replies to the parent.
            let turn: CGFloat = pulse.toSubagent != nil ? 1 : -1
            arc.addCurve(to: end, control1: CGPoint(x: start.x + 34, y: start.y - 20 * turn),
                         control2: CGPoint(x: start.x + 34, y: start.y + 20 * turn))
        } else if abs(start.x - end.x) > abs(start.y - end.y) {
            // Parent halo to its own subagent dot within the row: bow above the row.
            arc.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - 14))
        } else {
            let control = CGPoint(x: max(2, min(start.x, end.x) - 10 - abs(end.y - start.y) * 0.25), y: (start.y + end.y) / 2)
            arc.addQuadCurve(to: end, control: control)
        }
        context.stroke(arc, with: .color(color.opacity(0.32 * (1 - progress))),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [2, 4]))
        if progress < 0.3 {
            drawRipple(&context, at: start, color: color, progress: progress / 0.3 * 0.6)
        }
        let travel = min(1, progress / 0.72)
        if travel < 1 {
            let head = travel * travel * (3 - 2 * travel)
            let trail = arc.trimmedPath(from: max(0, head - 0.3), to: head)
            context.stroke(trail, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            if let tip = arc.trimmedPath(from: 0, to: max(0.001, head)).currentPoint {
                context.fill(Path(ellipseIn: CGRect(x: tip.x - 6, y: tip.y - 6, width: 12, height: 12)), with: .color(color.opacity(0.28)))
                context.fill(Path(ellipseIn: CGRect(x: tip.x - 2.6, y: tip.y - 2.6, width: 5.2, height: 5.2)), with: .color(.white))
            }
        }
        if progress > 0.62 {
            drawRipple(&context, at: end, color: color, progress: (progress - 0.62) / 0.38)
        }
    }

    private func drawRipple(_ context: inout GraphicsContext, at point: CGPoint, color: Color, progress: Double) {
        let radius = 3 + 12 * progress
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.stroke(Path(ellipseIn: rect), with: .color(color.opacity(0.85 * (1 - progress))), lineWidth: 1.6)
    }
}

private struct ProgressTrack: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(color).frame(width: max(3, proxy.size.width * min(1, max(0, fraction))))
            }
        }
    }
}

// MARK: - Traffic identity

struct TrafficKey: Hashable {
    let from: UInt64
    let fromSubagent: String?
    let to: UInt64
    let toSubagent: String?
    let kind: String
    let text: String
    let sent: Int64?
    let reply: Bool
    init(_ item: TernMessage) {
        from = item.from.pane; fromSubagent = item.from.subagent
        to = item.to.pane; toSubagent = item.to.subagent
        kind = item.kind; text = item.text; sent = item.sentMs; reply = item.reply
    }
}

struct TrafficEntry: Identifiable {
    struct ID: Hashable { let key: TrafficKey; let occurrence: Int }
    let id: ID
    let item: TernMessage
    let offset: Int
    let time: String
    let preview: String
    init(id: ID, item: TernMessage, offset: Int) {
        self.id = id; self.item = item; self.offset = offset
        time = (item.sentMs ?? item.deliveredMs).map { Self.clock.string(from: Date(timeIntervalSince1970: Double($0) / 1000)) } ?? "--:--:--"
        preview = item.text.isEmpty ? "(Empty message)" : String(item.text.prefix(240)).replacingOccurrences(of: "\n", with: " ")
    }
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct TrafficPulse: Identifiable {
    let id = UUID()
    let entry: TrafficEntry.ID
    let from: UInt64
    let fromSubagent: String?
    let to: UInt64
    let toSubagent: String?
    let failed: Bool
    let started: Date
}

// MARK: - Formatting

func agentName(_ agent: TernAgent) -> String {
    for candidate in [agent.label, agent.title] {
        let name = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = name.replacingOccurrences(of: "-", with: "")
        let isOpaque = name == String(agent.pane) || (identifier.count >= 20 && identifier.allSatisfy(\.isHexDigit))
        if !name.isEmpty && !isOpaque { return name }
    }
    let repository = agent.cwd.isEmpty ? "" : URL(fileURLWithPath: agent.cwd).lastPathComponent
    return repository.isEmpty ? "Agent · tab \(agent.tab)" : "\(repository) · t\(agent.tab)"
}

private func agentStatus(_ agent: TernAgent) -> String {
    if !agent.open { return "closed" }
    if agent.working { return agent.tool.map { $0.name.isEmpty ? "working" : $0.name } ?? "working" }
    if agent.subagents.contains(where: \.running) { return "orchestrating" }
    return "idle"
}

private func activityLine(_ agent: TernAgent) -> String {
    if let tool = agent.tool {
        let intent = tool.intent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !intent.isEmpty { return tool.name.isEmpty ? intent : "\(tool.name) · \(intent)" }
        if !tool.name.isEmpty { return tool.name }
    }
    let running = agent.subagents.filter(\.running).count
    if !agent.working && running > 0 { return "waiting on \(running) subagent\(running == 1 ? "" : "s")" }
    if !agent.description.isEmpty { return agent.description }
    return agent.working ? "working" : "idle"
}

private func agentHeadline(_ agent: TernAgent) -> String {
    var parts = [agentStatus(agent)]
    if agent.open && !agent.working { parts.append("quiet \(quietLabel(agent.quietMs))") }
    if let model = agent.model, !model.isEmpty { parts.append(model) } else if let cli = agent.cli, !cli.isEmpty { parts.append(cli) }
    parts.append("\(tokenLabel(agent.tokens)) tokens")
    return parts.joined(separator: " · ")
}

private func locationLine(_ agent: TernAgent) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let cwd = agent.cwd.hasPrefix(home) ? "~" + agent.cwd.dropFirst(home.count) : agent.cwd
    return "pane \(agent.pane) · tab \(agent.tab)" + (cwd.isEmpty ? "" : " · \(cwd)")
}

private func quietLabel(_ milliseconds: UInt64) -> String {
    let seconds = milliseconds / 1000
    if seconds < 60 { return "\(seconds)s" }
    if seconds < 3600 { return "\(seconds / 60)m" }
    if seconds < 86_400 { return "\(seconds / 3600)h" }
    return "\(seconds / 86_400)d"
}

private func tokenLabel(_ tokens: UInt64) -> String {
    if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000) }
    if tokens >= 1_000 { return String(format: "%.1fk", Double(tokens) / 1_000) }
    return String(tokens)
}

private func delivery(_ message: TernMessage) -> String {
    if message.failed { return message.outcome.flatMap { $0.isEmpty ? nil : $0 } ?? "Failed" }
    if let outcome = message.outcome, !outcome.isEmpty { return outcome }
    if message.deliveredMs != nil { return "Delivered" }
    return message.deliveryObservable ? "Awaiting delivery" : "Delivery unknown"
}

private func deliveryColor(_ message: TernMessage) -> Color {
    if message.failed { return Color.red }
    if message.deliveredMs != nil { return Color.green.opacity(0.85) }
    return Color.white.opacity(message.deliveryObservable ? 0.45 : 0.35)
}
