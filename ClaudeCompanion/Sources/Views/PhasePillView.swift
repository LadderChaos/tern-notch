import SwiftUI

/// A single phase pill showing icon, label, progress bar, and step counter.
/// Matches the collapsed state shown in the demo (e.g., "🔍 Researching ━━━━ 1/4")
struct PhasePillView: View {
    let phase: Phase
    let progress: Double
    let isActive: Bool
    let isCompleted: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Phase icon
                Image(systemName: phase.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isActive ? accentColor : CompanionTheme.textSecondary)

                // Phase label
                Text(phase.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isActive ? CompanionTheme.textPrimary : CompanionTheme.textSecondary)

                Spacer()

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track
                        Capsule()
                            .fill(CompanionTheme.divider)
                            .frame(height: CompanionTheme.progressBarHeight)

                        // Fill
                        Capsule()
                            .fill(accentColor)
                            .frame(
                                width: max(0, geo.size.width * progress),
                                height: CompanionTheme.progressBarHeight
                            )
                            .animation(CompanionTheme.progressAnimation, value: progress)
                    }
                    .frame(height: CompanionTheme.progressBarHeight)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .frame(width: 80, height: CompanionTheme.progressBarHeight)

                // Step counter
                HStack(spacing: 2) {
                    Text("\(phase.stepNumber)")
                        .foregroundColor(CompanionTheme.textPrimary)
                    Text("/\(Phase.totalSteps)")
                        .foregroundColor(CompanionTheme.textMuted)
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: CompanionTheme.pillCornerRadius)
                    .fill(isActive ? CompanionTheme.cardBackground : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var accentColor: Color {
        CompanionTheme.color(for: phase)
    }
}
