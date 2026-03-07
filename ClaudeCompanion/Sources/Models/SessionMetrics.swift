import Foundation

/// Real-time metrics for the current coding agent session
struct SessionMetrics: Equatable {
    var tokenCount: Int = 0
    var latencyMs: Int = 0
    var modelName: String = "Opus 4.6"
    var source: AgentSource = .unknown
    var isActive: Bool = false

    /// Formatted token count (e.g., "19.800" or "19,800")
    var formattedTokens: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "de_DE") // Period as thousands separator
        return formatter.string(from: NSNumber(value: tokenCount)) ?? "\(tokenCount)"
    }

    /// Formatted latency string
    var formattedLatency: String {
        "\(latencyMs)ms"
    }
}

/// Aggregated session state combining all telemetry
struct SessionState: Equatable {
    var currentPhase: Phase = .researching
    var phaseProgress: [Phase: Double] = [
        .researching: 0,
        .reasoning: 0,
        .writing: 0,
        .reviewing: 0
    ]
    var phaseCompleted: [Phase: Bool] = [
        .researching: false,
        .reasoning: false,
        .writing: false,
        .reviewing: false
    ]
    var toolCalls: [ToolCallCategory] = []
    var metrics: SessionMetrics = SessionMetrics()
    var startTime: Date = Date()

    /// Whether any activity has been recorded
    var hasActivity: Bool {
        metrics.tokenCount > 0 || !toolCalls.isEmpty
    }
}
