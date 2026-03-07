import SwiftUI

/// Design tokens matching the demo UI
enum CompanionTheme {
    // MARK: - Colors
    static let panelBackground = Color(red: 0.08, green: 0.08, blue: 0.10)
    static let cardBackground = Color(red: 0.12, green: 0.12, blue: 0.14)
    static let cardBackgroundHover = Color(red: 0.15, green: 0.15, blue: 0.17)
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.55, green: 0.55, blue: 0.60)
    static let textMuted = Color(red: 0.40, green: 0.40, blue: 0.45)
    static let divider = Color(red: 0.20, green: 0.20, blue: 0.22)
    static let green = Color(red: 0.0, green: 0.87, blue: 0.62)  // Latency green

    // Agent source colors
    static let claudeOrange = Color(red: 0.95, green: 0.55, blue: 0.20) // Claude Code
    static let codexBlue = Color(red: 0.30, green: 0.55, blue: 0.95)    // OpenAI Codex
    static let unknownBlue = Color(red: 0.55, green: 0.75, blue: 0.85)  // Unknown agent

    // Phase colors
    static let phaseResearching = Color(red: 0.45, green: 0.35, blue: 0.85) // Purple
    static let phaseReasoning = Color(red: 0.90, green: 0.25, blue: 0.55)   // Pink
    static let phaseWriting = Color(red: 0.0, green: 0.85, blue: 0.85)      // Cyan
    static let phaseReviewing = Color(red: 0.90, green: 0.65, blue: 0.15)   // Orange/Amber

    // MARK: - Spacing
    static let cornerRadius: CGFloat = 16
    static let innerCornerRadius: CGFloat = 12
    static let pillCornerRadius: CGFloat = 20
    static let panelPadding: CGFloat = 12
    static let itemSpacing: CGFloat = 8

    // MARK: - Sizing
    static let notchWidth: CGFloat = 200
    static let notchHeight: CGFloat = 32
    static let expandedWidth: CGFloat = 380
    static let expandedHeight: CGFloat = 460
    static let pillHeight: CGFloat = 38
    static let progressBarHeight: CGFloat = 4

    // MARK: - Animation
    static let expandAnimation: Animation = .spring(response: 0.35, dampingFraction: 0.8)
    static let progressAnimation: Animation = .easeInOut(duration: 0.6)
    static let phaseTransition: Animation = .easeInOut(duration: 0.3)

    /// Get the accent color for a phase
    static func color(for phase: Phase) -> Color {
        switch phase {
        case .researching: phaseResearching
        case .reasoning: phaseReasoning
        case .writing: phaseWriting
        case .reviewing: phaseReviewing
        }
    }
}
