import SwiftUI

/// The 4 phases Claude Code progresses through during a task
enum Phase: Int, CaseIterable, Identifiable, Codable {
    case researching = 0
    case reasoning = 1
    case writing = 2
    case reviewing = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .researching: "Researching"
        case .reasoning: "Reasoning"
        case .writing: "Writing"
        case .reviewing: "Reviewing"
        }
    }

    var icon: String {
        switch self {
        case .researching: "magnifyingglass"
        case .reasoning: "bubble.left.fill"
        case .writing: "pencil.line"
        case .reviewing: "gearshape"
        }
    }

    var accentColor: Color {
        switch self {
        case .researching: .purple
        case .reasoning: .pink
        case .writing: .cyan
        case .reviewing: .orange
        }
    }

    /// Step number for display (1-indexed)
    var stepNumber: Int { rawValue + 1 }

    /// Total number of phases
    static var totalSteps: Int { allCases.count }
}
