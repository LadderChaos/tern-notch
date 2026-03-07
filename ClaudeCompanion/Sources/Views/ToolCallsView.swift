import SwiftUI

/// Shows the list of tool call categories with counts and recency.
/// Matches the demo layout:
///   Tool Calls
///   web_search         x3  2s ago
///   code_exec          x1  8s ago
///   file_read          x5  just now
struct ToolCallsView: View {
    let toolCalls: [ToolCallCategory]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Text("Tool Calls")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(CompanionTheme.textMuted)
                .textCase(.none)

            // Tool call rows
            ForEach(sortedCalls) { call in
                ToolCallRow(call: call)
            }
        }
    }

    /// Sort by most recent first
    private var sortedCalls: [ToolCallCategory] {
        toolCalls.sorted { $0.lastUsed > $1.lastUsed }
    }
}

private struct ToolCallRow: View {
    let call: ToolCallCategory

    var body: some View {
        HStack {
            // Tool name
            Text(call.name)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(CompanionTheme.textPrimary)

            Spacer()

            // Count badge
            Text("x\(call.count)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(CompanionTheme.green)

            // Recency
            Text(call.recency)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(CompanionTheme.textMuted)
                .frame(width: 55, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}
