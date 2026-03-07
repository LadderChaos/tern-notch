import SwiftUI

/// The expanded detail panel shown when a phase is tapped.
/// Contains: phase tab bar, tool calls list, and metrics bar.
struct DetailPanelView: View {
    @Binding var selectedPhase: Phase
    let state: SessionState

    var body: some View {
        VStack(spacing: 12) {
            // Phase tab bar
            PhaseTabBar(
                selectedPhase: $selectedPhase,
                completedPhases: state.phaseCompleted
            )

            // Divider
            CompanionTheme.divider.frame(height: 0.5)

            // Tool calls
            ToolCallsView(toolCalls: state.toolCalls)
                .padding(.horizontal, 4)

            Spacer(minLength: 0)

            // Metrics bar
            MetricsBar(metrics: state.metrics)
        }
        .padding(CompanionTheme.panelPadding)
        .background(
            RoundedRectangle(cornerRadius: CompanionTheme.cornerRadius)
                .fill(CompanionTheme.panelBackground)
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        )
        .frame(width: CompanionTheme.expandedWidth)
    }
}
