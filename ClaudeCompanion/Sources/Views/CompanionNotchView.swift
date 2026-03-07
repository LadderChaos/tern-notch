import SwiftUI

/// Main companion view that lives near the notch area.
/// Shows the 4-phase pipeline as stacked pills, with expandable detail panel.
struct CompanionNotchView: View {
    @ObservedObject var viewModel: CompanionViewModel
    @State private var isExpanded = false
    @State private var selectedPhase: Phase = .researching
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 6) {
            // Phase pills — always visible
            ForEach(Phase.allCases) { phase in
                let isActive = viewModel.state.currentPhase == phase
                let progress = viewModel.state.phaseProgress[phase] ?? 0
                let isCompleted = viewModel.state.phaseCompleted[phase] ?? false

                if phase == selectedPhase && isExpanded {
                    // Expanded: show detail panel for selected phase
                    expandedCard(for: phase, progress: progress)
                } else {
                    // Collapsed: show pill
                    PhasePillView(
                        phase: phase,
                        progress: progress,
                        isActive: isActive,
                        isCompleted: isCompleted
                    ) {
                        withAnimation(CompanionTheme.expandAnimation) {
                            if isExpanded && selectedPhase == phase {
                                isExpanded = false
                            } else {
                                selectedPhase = phase
                                isExpanded = true
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(backgroundShape)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .onChange(of: viewModel.state.currentPhase) { _, newPhase in
            withAnimation(CompanionTheme.phaseTransition) {
                selectedPhase = newPhase
            }
        }
    }

    // MARK: - Expanded Card

    @ViewBuilder
    private func expandedCard(for phase: Phase, progress: Double) -> some View {
        VStack(spacing: 0) {
            // Phase header with progress bar (matches pill layout)
            HStack(spacing: 10) {
                Image(systemName: phase.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CompanionTheme.color(for: phase))

                Text(phase.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(CompanionTheme.textPrimary)

                SourceBadge(source: viewModel.state.metrics.source)

                Spacer()

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(CompanionTheme.divider)
                            .frame(height: CompanionTheme.progressBarHeight)
                        Capsule()
                            .fill(CompanionTheme.color(for: phase))
                            .frame(
                                width: max(0, geo.size.width * progress),
                                height: CompanionTheme.progressBarHeight
                            )
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
            .padding(.top, 12)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(CompanionTheme.expandAnimation) {
                    isExpanded = false
                }
            }

            // Detail panel content
            DetailPanelView(
                selectedPhase: $selectedPhase,
                state: viewModel.state
            )
        }
        .background(
            RoundedRectangle(cornerRadius: CompanionTheme.cornerRadius)
                .fill(CompanionTheme.panelBackground)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        )
    }

    // MARK: - Background

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: CompanionTheme.cornerRadius + 4)
            .fill(.ultraThinMaterial)
            .opacity(isHovering ? 0.3 : 0)
    }
}
