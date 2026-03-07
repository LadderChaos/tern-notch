import SwiftUI

/// Small colored dot + label indicating which AI agent is active.
/// Orange dot for Claude, blue dot for Codex.
struct SourceIndicator: View {
    let source: AgentSource
    var showLabel: Bool = true
    var size: CGFloat = 8

    var body: some View {
        HStack(spacing: 5) {
            // Pulsing dot
            Circle()
                .fill(source.color)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .fill(source.color.opacity(0.4))
                        .frame(width: size + 4, height: size + 4)
                        .scaleEffect(pulseScale)
                        .animation(
                            .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                            value: pulseScale
                        )
                )

            if showLabel {
                Text(source.shortName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(source.color)
            }
        }
        .onAppear { pulseScale = 1.3 }
    }

    @State private var pulseScale: CGFloat = 1.0
}

/// Compact inline source badge for use in tight spaces
struct SourceBadge: View {
    let source: AgentSource

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(source.color)
                .frame(width: 6, height: 6)
            Text(source.shortName)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(source.color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(source.color.opacity(0.12))
        )
    }
}
