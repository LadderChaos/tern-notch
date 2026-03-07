import Foundation

/// Represents a category of tool calls made by Claude Code
struct ToolCallCategory: Identifiable, Equatable {
    let id: String
    let name: String
    var count: Int
    var lastUsed: Date

    /// Human-readable time since last use
    var recency: String {
        let seconds = Int(Date().timeIntervalSince(lastUsed))
        if seconds < 1 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}

/// Known Claude Code tool types mapped to display names
enum ToolType: String, CaseIterable {
    case webSearch = "web_search"
    case codeExec = "code_exec"
    case fileRead = "file_read"
    case fileWrite = "file_write"
    case bash = "bash"
    case grep = "grep"
    case glob = "glob"
    case edit = "edit"
    case agent = "agent"

    var displayName: String {
        switch self {
        case .webSearch: "web_search"
        case .codeExec: "code_exec"
        case .fileRead: "file_read"
        case .fileWrite: "file_write"
        case .bash: "bash"
        case .grep: "grep"
        case .glob: "glob"
        case .edit: "edit"
        case .agent: "agent"
        }
    }
}
