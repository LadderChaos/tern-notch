//
//  ClaudeCodeModels.swift
//  boringNotch
//
//  Models for Claude Code session monitoring
//

import Foundation

// MARK: - Agent Type

enum AgentType: String, Equatable {
    case claude
    case codex
    case opencode

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        }
    }
}

// MARK: - Session Discovery

/// Represents an active AI coding agent session
struct ClaudeSession: Identifiable, Equatable {
    /// Unique ID = JSONL filename (UUID) for uniqueness across sessions in same project
    let id: String

    /// The project directory key under ~/.claude/projects/
    let projectKey: String

    /// Full path to the JSONL file being watched
    let jsonlPath: String

    /// IDE info (from lock file, if available)
    let pid: Int
    let ideName: String
    let isTerminalSession: Bool
    let agentType: AgentType

    var displayName: String {
        // For Codex/OpenCode: use cwd-based project key or fallback
        if agentType == .codex || agentType == .opencode {
            // For non-Claude agents, extract project name from projectKey (cwd-based)
            let key = projectKey.hasPrefix("-") ? String(projectKey.dropFirst()) : projectKey
            // Try to find last meaningful path component
            let components = key.components(separatedBy: "-")
            if let last = components.last, !last.isEmpty { return last }
            return agentType.displayName
        }

        // Project key is path with / replaced by - e.g. "-Users-username-GitHub-project"
        let key = projectKey.hasPrefix("-") ? String(projectKey.dropFirst()) : projectKey
        let patterns = ["-GitHub-", "-Desktop-", "-Documents-", "-Projects-", "-projects-", "-code-", "-src-"]
        for pattern in patterns {
            if let range = key.range(of: pattern, options: .backwards) {
                return String(key[range.upperBound...])
            }
        }
        if let usersRange = key.range(of: "Users-") {
            let afterUsers = key[usersRange.upperBound...]
            if let dashRange = afterUsers.range(of: "-") {
                return String(afterUsers[dashRange.upperBound...])
            }
        }
        return projectKey
    }
}

struct ClaudeSessionLockFile: Codable {
    let pid: Int
    let workspaceFolders: [String]
    let ideName: String
    let transport: String?
    let runningInWindows: Bool?

    /// Convert workspace path to project key (matching ~/.claude/projects/ dir naming)
    var projectKey: String? {
        guard let workspace = workspaceFolders.first else { return nil }
        return workspace
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }
}

// MARK: - Token Usage

struct TokenUsage: Equatable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadInputTokens: Int = 0
    var cacheCreationInputTokens: Int = 0

    /// Tokens currently in context window (latest request's input + cache_read + output)
    var contextTokens: Int = 0

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadInputTokens + cacheCreationInputTokens
    }

    static let contextWindow = 200_000

    var contextPercentage: Double {
        guard Self.contextWindow > 0 else { return 0 }
        let used = contextTokens > 0 ? contextTokens : (inputTokens + cacheReadInputTokens + outputTokens)
        return min(100, Double(used) / Double(Self.contextWindow) * 100)
    }
}

// MARK: - Tool Execution

struct ToolExecution: Identifiable, Equatable {
    let id: String
    let toolName: String
    let argument: String?
    let startTime: Date
    var endTime: Date?
    var isRunning: Bool { endTime == nil }

    var durationMs: Int? {
        guard let end = endTime else { return nil }
        return Int(end.timeIntervalSince(startTime) * 1000)
    }
}

// MARK: - Todo Item

struct ClaudeTodoItem: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let status: TodoStatus

    enum TodoStatus: String {
        case pending
        case inProgress = "in_progress"
        case completed
    }
}

// MARK: - Complete State

struct ClaudeCodeState: Equatable {
    var sessionId: String = ""
    var model: String = ""
    var cwd: String = ""
    var gitBranch: String = ""
    var tokenUsage: TokenUsage = TokenUsage()
    var lastMessage: String = ""
    var lastMessageTime: Date?
    var activeTools: [ToolExecution] = []
    var recentTools: [ToolExecution] = []
    var todos: [ClaudeTodoItem] = []
    var permissionMode: String = ""
    var isConnected: Bool = false
    var lastUpdateTime: Date?
    var needsPermission: Bool = false
    var pendingPermissionTool: String?
    var isThinking: Bool = false

    var contextPercentage: Double { tokenUsage.contextPercentage }
    var hasActiveTools: Bool { !activeTools.isEmpty }
    var currentToolName: String? { activeTools.first?.toolName }
    var isActive: Bool { isThinking || hasActiveTools }
}

// MARK: - Daily Stats

struct DailyStats: Equatable {
    var messageCount: Int = 0
    var toolCallCount: Int = 0
    var sessionCount: Int = 0
    var tokensUsed: Int = 0
    var date: String = ""
    var isEmpty: Bool { date.isEmpty }
}

struct StatsCache: Codable {
    let dailyActivity: [DailyActivity]?
    let dailyModelTokens: [DailyModelTokens]?

    struct DailyActivity: Codable {
        let date: String
        let messageCount: Int?
        let sessionCount: Int?
        let toolCallCount: Int?
    }

    struct DailyModelTokens: Codable {
        let date: String
        let tokensByModel: [String: Int]?
    }
}
