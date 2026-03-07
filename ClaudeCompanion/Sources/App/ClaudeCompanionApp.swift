import SwiftUI

/// Claude Companion — A macOS notch companion for Claude Code.
///
/// Displays real-time Claude Code activity in the MacBook notch area:
/// - 4-phase pipeline: Researching → Reasoning → Writing → Reviewing
/// - Tool call tracking with counts and recency
/// - Token usage, latency, and model metrics
///
/// Setup:
///   export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4318"
///   claude  # start Claude Code — telemetry will appear in the notch
///
/// Inspired by boringnotch (github.com/TheBoredTeam/boring.notch)
@main
struct ClaudeCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible window — everything is in the notch panel + menu bar
        Settings {
            EmptyView()
        }
    }
}
