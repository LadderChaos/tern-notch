import SwiftUI

/// Horizontal tab bar for switching between phases in the detail panel.
/// Shows all 4 phases with icons, labels, and colored underline indicators.
struct PhaseTabBar: View {
    @Binding var selectedPhase: Phase
    let completedPhases: [Phase: Bool]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Phase.allCases) { phase in
                PhaseTab(
                    phase: phase,
                    isSelected: selectedPhase == phase,
                    isCompleted: completedPhases[phase] ?? false
                )
                .onTapGesture {
                    withAnimation(CompanionTheme.phaseTransition) {
                        selectedPhase = phase
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct PhaseTab: View {
    let phase: Phase
    let isSelected: Bool
    let isCompleted: Bool

    var body: some View {
        VStack(spacing: 6) {
            // Icon
            Image(systemName: phase.icon)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? accentColor : CompanionTheme.textMuted)

            // Label
            Text(phase.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isSelected ? CompanionTheme.textPrimary : CompanionTheme.textMuted)

            // Underline indicator
            RoundedRectangle(cornerRadius: 1)
                .fill(isSelected ? accentColor : (isCompleted ? CompanionTheme.textMuted : Color.clear))
                .frame(height: 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: CompanionTheme.innerCornerRadius)
                .fill(isSelected ? accentColor.opacity(0.12) : Color.clear)
        )
    }

    private var accentColor: Color {
        CompanionTheme.color(for: phase)
    }
}
