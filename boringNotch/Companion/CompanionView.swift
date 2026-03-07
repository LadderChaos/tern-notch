//
//  CompanionView.swift
//  boringNotch
//
//  Persistent HUD for AI coding agent sessions.
//  Two cards half-half, vertical divider.
//  Active sessions sorted left. Click background to dismiss.
//

import SwiftUI

struct CompanionView: View {
    @ObservedObject var manager = CompanionManager.shared
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    coordinator.currentView = .home
                    vm.close()
                }

            if manager.sessions.isEmpty {
                emptyState
            } else {
                sessionContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.title3)
                .foregroundColor(.secondary.opacity(0.5))
            Text("No active sessions")
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.6))
        }
    }

    private var sessionContent: some View {
        let sorted = sortedSessions
        let pageCount = max(1, (sorted.count + 1) / 2)  // 2 cards per page

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(0..<pageCount, id: \.self) { page in
                    HStack(spacing: 4) {
                        let i1 = page * 2
                        let i2 = page * 2 + 1

                        SessionCardView(info: sorted[i1])

                        if i2 < sorted.count {
                            SessionCardView(info: sorted[i2])
                        } else {
                            Color.clear
                        }
                    }
                    .padding(.horizontal, 6)
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
    }

    private var sortedSessions: [CompanionManager.SessionInfo] {
        manager.sessions.sorted { a, b in
            func priority(_ s: CompanionManager.SessionInfo) -> Int {
                if s.state.needsPermission { return 0 }
                if s.state.isActive { return 1 }
                return 2
            }
            let pa = priority(a), pb = priority(b)
            if pa != pb { return pa < pb }
            // Same priority: sort by most recent update
            let ta = a.state.lastUpdateTime ?? .distantPast
            let tb = b.state.lastUpdateTime ?? .distantPast
            return ta > tb
        }
    }
}

// MARK: - Session Card

struct SessionCardView: View {
    let info: CompanionManager.SessionInfo

    private var s: ClaudeCodeState { info.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.bottom, 4)
            contextRow
                .padding(.bottom, 8)

            activityRow
                .padding(.bottom, 4)
            todosRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .background(agentBackground)
        .overlay {
            if s.needsPermission {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(agentBackgroundColor.opacity(0.6), lineWidth: 1.5)
            }
        }
    }

    private var agentBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(agentBackgroundColor.opacity(0.04))
    }

    private var agentBackgroundColor: Color {
        switch info.session.agentType {
        case .claude: return .orange
        case .codex: return .green
        case .opencode: return .blue
        }
    }

    // MARK: - Row 1: project/branch ... mode/model

    private var headerRow: some View {
        HStack(spacing: 0) {
            // Left: name + branch
            HStack(spacing: 5) {
                Text(info.session.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if !s.gitBranch.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9))
                        Text(s.gitBranch)
                            .font(.system(size: 10))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white.opacity(0.35))
                }
            }

            Spacer(minLength: 8)

            // Right: badges
            HStack(spacing: 4) {
                if !s.permissionMode.isEmpty {
                    badgeView(
                        modeLabel(s.permissionMode),
                        color: s.permissionMode == "bypassPermissions" ? .green : .orange
                    )
                }
                if !s.model.isEmpty {
                    badgeView(modelShort(s.model), color: .white)
                }
            }
        }
    }

    // MARK: - Row 2: In ... Out ... [bar] %

    private var contextRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                tokenLabel("In", s.tokenUsage.inputTokens + s.tokenUsage.cacheReadInputTokens)
                tokenLabel("Out", s.tokenUsage.outputTokens)
            }

            Spacer(minLength: 8)

            ContextBar(percentage: s.contextPercentage)
        }
    }

    private func tokenLabel(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.35))
            Text(formatTokens(value))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    // MARK: - Row 3: activity (2 lines max)

    @ViewBuilder
    private var activityRow: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Image(systemName: activityIcon)
                    .font(.system(size: 11))
                Text(activityLabel)
                    .font(.system(size: 12, weight: .medium))
                if let ms = activityDurationMs {
                    Text("\(ms)ms")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(activityColor.opacity(0.5))
                }
            }
            .foregroundColor(activityColor)

            if let detail = activityDetail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(activityColor.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Row 4: todos (always)

    private var todosRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "checklist")
                .font(.system(size: 10))
            if s.todos.isEmpty {
                Text("No tasks")
                    .font(.system(size: 10))
            } else {
                let done = s.todos.filter { $0.status == .completed }.count
                let inProgress = s.todos.filter { $0.status == .inProgress }.count
                Text("\(done)/\(s.todos.count) done")
                    .font(.system(size: 10, weight: .medium))
                if inProgress > 0 {
                    Text("\(inProgress) active")
                        .font(.system(size: 10))
                        .foregroundColor(.cyan.opacity(0.7))
                }
            }
        }
        .foregroundColor(.white.opacity(0.3))
    }

    // MARK: - Activity state

    private var activityIcon: String {
        if s.needsPermission { return "exclamationmark.triangle.fill" }
        if let tool = s.activeTools.first { return toolIcon(tool.toolName) }
        if s.isThinking { return "brain" }
        if s.recentTools.first != nil { return "checkmark.circle" }
        return "moon.zzz"
    }

    private var activityLabel: String {
        if s.needsPermission { return s.pendingPermissionTool ?? "Permission" }
        if let tool = s.activeTools.first { return tool.toolName }
        if s.isThinking { return "Thinking" }
        if let recent = s.recentTools.first {
            return recent.toolName
        }
        return "Idle"
    }

    private var activityDetail: String? {
        if s.needsPermission { return "waiting" }
        if let tool = s.activeTools.first { return tool.argument }
        if let recent = s.recentTools.first { return recent.argument }
        return nil
    }

    private var activityDurationMs: Int? {
        if let recent = s.recentTools.first, !s.isThinking && s.activeTools.isEmpty && !s.needsPermission {
            return recent.durationMs
        }
        return nil
    }

    private var activityColor: Color {
        if s.needsPermission { return .orange }
        if s.activeTools.first != nil { return .green }
        if s.isThinking { return .cyan.opacity(0.8) }
        if s.recentTools.first != nil { return .white.opacity(0.5) }
        return .white.opacity(0.3)
    }

    // MARK: - Styling

    private var statusColor: Color {
        s.needsPermission ? .orange : s.isActive ? .green : .gray.opacity(0.5)
    }

    private func badgeView(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(color.opacity(0.7))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.1)))
    }

    private func modeLabel(_ mode: String) -> String {
        switch mode {
        case "bypassPermissions": return "YOLO"
        case "acceptEdits": return "Auto"
        case "default": return "Ask"
        case "plan": return "Plan"
        default: return mode
        }
    }

    private func modelShort(_ model: String) -> String {
        // Strip parenthetical suffix e.g. "Sisyphus (Ultraworker)" → "Sisyphus"
        let cleaned = model.contains("(") ? String(model.prefix(while: { $0 != "(" })).trimmingCharacters(in: .whitespaces) : model
        let m = cleaned.lowercased()
        if m.contains("opus") { return "Opus" }
        if m.contains("sonnet") { return "Sonnet" }
        if m.contains("haiku") { return "Haiku" }
        if m.contains("gpt-5") { return "GPT-5" }
        if m.contains("gpt-4") { return "GPT-4" }
        if m.contains("gemini") { return "Gemini" }
        if m.contains("o3") || m.contains("o4") { return cleaned }
        if m.contains("deepseek") { return "DeepSeek" }
        if m.contains("qwen") { return "Qwen" }
        if m == "openai" || m == "anthropic" { return m.capitalized }
        // For unknown models, return cleaned name truncated
        if cleaned.count > 10 { return String(cleaned.prefix(10)) }
        return cleaned.isEmpty ? "AI" : cleaned
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fk", Double(count) / 1_000) }
        return "\(count)"
    }

    private func toolIcon(_ name: String) -> String {
        switch name.lowercased() {
        case "bash", "shell", "execute": return "terminal.fill"
        case "read", "readfile": return "doc.text.fill"
        case "write", "edit", "writefile", "editfile": return "pencil.line"
        case "glob", "listfiles": return "magnifyingglass"
        case "grep", "search": return "text.magnifyingglass"
        case "task", "agent": return "person.fill"
        case "webfetch", "websearch": return "globe"
        default: return "gearshape.fill"
        }
    }
}

// MARK: - Context Bar

struct ContextBar: View {
    let percentage: Double

    private var color: Color {
        percentage > 80 ? .red : percentage > 60 ? .orange : .green
    }

    var body: some View {
        HStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.15))
                    Capsule().fill(color)
                        .frame(width: max(0, geo.size.width * min(1, percentage / 100)))
                }
            }
            .frame(width: 50, height: 4)

            Text("\(Int(percentage))%")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }
}

// MARK: - Thinking Dots

struct ThinkingDots: View {
    @State private var dotIndex = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.cyan.opacity(i == dotIndex ? 0.9 : 0.25))
                    .frame(width: 4, height: 4)
            }
        }
        .onReceive(timer) { _ in dotIndex = (dotIndex + 1) % 3 }
    }
}
