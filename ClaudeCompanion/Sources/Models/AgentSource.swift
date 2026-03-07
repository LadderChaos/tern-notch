import SwiftUI

/// The AI coding agent source being monitored.
/// Determines indicator color and display name.
enum AgentSource: String, CaseIterable, Identifiable, Codable, Equatable {
    case claude = "claude"
    case codex = "codex"
    case unknown = "unknown"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .unknown: "Unknown"
        }
    }

    var shortName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .unknown: "Agent"
        }
    }

    /// Indicator color — orange for Claude, blue for Codex (matching AgentNotch convention)
    var color: Color {
        switch self {
        case .claude: Color(red: 0.95, green: 0.55, blue: 0.20)   // Orange
        case .codex: Color(red: 0.30, green: 0.55, blue: 0.95)    // Blue
        case .unknown: Color(red: 0.55, green: 0.75, blue: 0.85)  // Light blue
        }
    }

    var icon: String {
        switch self {
        case .claude: "brain.head.profile"
        case .codex: "terminal"
        case .unknown: "questionmark.circle"
        }
    }

    /// Detect source from OTLP resource attributes or service name
    static func detect(from serviceName: String?, modelName: String?) -> AgentSource {
        let combined = ((serviceName ?? "") + " " + (modelName ?? "")).lowercased()

        if combined.contains("claude") || combined.contains("anthropic") || combined.contains("opus") || combined.contains("sonnet") || combined.contains("haiku") {
            return .claude
        }
        if combined.contains("codex") || combined.contains("openai") || combined.contains("gpt") {
            return .codex
        }
        return .unknown
    }
}
