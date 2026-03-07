import SwiftUI

/// Bottom metrics bar showing Tokens, Latency, and Model.
/// Layout matches demo:
///   Tokens      Latency      Model
///   19.800      143ms        Opus 4.6
struct MetricsBar: View {
    let metrics: SessionMetrics

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                MetricColumn(label: "Tokens", value: metrics.formattedTokens, color: CompanionTheme.textPrimary)
                MetricColumn(label: "Latency", value: metrics.formattedLatency, color: CompanionTheme.green)
                MetricColumn(label: "Model", value: metrics.modelName, color: CompanionTheme.textPrimary)
            }

            // Source indicator
            SourceIndicator(source: metrics.source)
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            CompanionTheme.divider.frame(height: 0.5)
        }
    }
}

private struct MetricColumn: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(CompanionTheme.textMuted)

            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }
}
