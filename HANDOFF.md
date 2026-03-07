# Handoff: Claude Companion

## What Is This

A macOS notch companion app that shows real-time AI coding agent activity (Claude Code + Codex) via OpenTelemetry. Lives below the MacBook notch, zero screen real estate. Think AgentNotch but built from scratch in Swift.

## Current State

**Branch:** `claude/add-companion-feature-vQqg6`
**Commits:** 2 (initial app + Codex support)
**Status:** Functional prototype — UI complete, OTLP receiver works, not yet tested against live telemetry

### What's Built

| Layer | Files | Status |
|-------|-------|--------|
| OTLP HTTP Server | `OTLPReceiver.swift` | Listens on `:4318`, parses logs/metrics/traces |
| Agent Detection | `AgentSource.swift` | Auto-detects Claude (orange) vs Codex (blue) from OTLP resource attrs |
| Phase Pipeline | `Phase.swift`, `PhasePillView.swift` | 4 phases: Researching → Reasoning → Writing → Reviewing |
| Expanded Panel | `DetailPanelView.swift`, `PhaseTabBar.swift` | Click phase pill → detail view with tool calls + metrics |
| Tool Tracking | `ToolCallsView.swift`, `ToolCall.swift` | Categorized tool calls with counts and recency |
| Metrics | `MetricsBar.swift`, `SessionMetrics.swift` | Tokens, latency, model name |
| Source Indicator | `SourceIndicator.swift` | Pulsing dot + badge (orange=Claude, blue=Codex) |
| Notch Window | `NotchWindow.swift` | NSPanel positioned at screen top-center, non-activating |
| App Lifecycle | `AppDelegate.swift` | Menu bar icon, toggle/demo/reset actions |
| Theme | `CompanionTheme.swift` | Dark theme tokens, animations, sizing constants |

### Architecture

```
OTLP (localhost:4318)
  ├── POST /v1/logs    → tool calls, phase changes
  ├── POST /v1/metrics → token count, latency, model
  └── POST /v1/traces  → spans (Codex)
       │
       ▼
  OTLPReceiver (NWListener TCP)
       │ detectSource() → AgentSource (.claude/.codex/.unknown)
       ▼
  CompanionViewModel (@MainActor, ObservableObject)
       │ state: SessionState (phases, tool calls, metrics)
       ▼
  CompanionNotchView (SwiftUI)
       ├── PhasePillView × 4 (collapsed)
       └── expandedCard (detail panel + MetricsBar + SourceBadge)
```

## What's NOT Done

1. **No live testing** — Haven't verified against actual Claude Code OTLP output. Demo mode works (`loadDemoData()`), but real telemetry format may differ.
2. **Phase detection is simulated** — `tickPhaseProgress()` auto-advances phases on a timer. Real phase detection from OTLP events needs mapping (which OTLP attributes map to which phase).
3. **No protobuf** — OTLP receiver only handles JSON. Claude Code may send protobuf (`application/x-protobuf`). Would need SwiftProtobuf dependency.
4. **No persistence** — Session resets on app restart. No history.
5. **No multi-session** — Can only track one agent at a time. Simultaneous Claude + Codex would overwrite each other's source.
6. **Window positioning** — Hardcoded to top-center. Not dynamically aligned to actual notch position on multi-monitor setups.
7. **No signing/notarization** — Can't distribute without Apple Developer account setup.

## How to Test

```bash
# Build
cd apps/companion/ClaudeCompanion
swift build

# Run (shows in menu bar + notch area)
swift run

# Or open in Xcode
open Package.swift
```

The app loads demo data on launch (`AppDelegate.swift:25`). Remove `viewModel.loadDemoData()` for production.

## Key Decisions

- **NWListener over Vapor/Hummingbird** — Zero dependencies, just Apple's Network framework. Keeps the app tiny.
- **JSON parsing via JSONSerialization** — No Codable models for OTLP because the schema is deeply nested and varies. Manual extraction is simpler.
- **Source detection is heuristic** — Matches on service name / model name strings. Not 100% reliable but good enough for Claude/Codex differentiation.
- **SwiftUI over AppKit** — All views are SwiftUI. Only AppKit usage is `NSPanel` (for non-activating floating window) and `NSStatusItem` (menu bar).

## Files Quick Reference

```
Sources/
├── App/
│   ├── ClaudeCompanionApp.swift   # @main, creates AppDelegate
│   ├── AppDelegate.swift          # Menu bar + window lifecycle
│   └── NotchWindow.swift          # NSPanel at screen top
├── Models/
│   ├── AgentSource.swift          # .claude/.codex enum + detection
│   ├── Phase.swift                # 4 phases, icons, colors
│   ├── ToolCall.swift             # Tool call category model
│   └── SessionMetrics.swift       # Tokens, latency, model, source
├── Views/
│   ├── CompanionNotchView.swift   # Main view (pills + expanded)
│   ├── PhasePillView.swift        # Collapsed pill row
│   ├── PhaseTabBar.swift          # Tab bar in detail panel
│   ├── DetailPanelView.swift      # Expanded content
│   ├── ToolCallsView.swift        # Tool call list
│   ├── MetricsBar.swift           # Bottom metrics row
│   └── SourceIndicator.swift      # Pulsing dot + badge
├── ViewModels/
│   └── CompanionViewModel.swift   # State + telemetry binding
├── Telemetry/
│   └── OTLPReceiver.swift         # HTTP server (NWListener)
└── Theme/
    └── CompanionTheme.swift       # Design tokens
```

## Next Steps (Suggested Priority)

1. **Verify OTLP format** — Run Claude Code with `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318` and log raw payloads to see actual schema
2. **Map real phases** — Determine which OTLP events correspond to researching/reasoning/writing/reviewing
3. **Handle protobuf** — Add `Content-Type` header check, fall back to protobuf parsing if not JSON
4. **Multi-session support** — Track multiple agents simultaneously with separate state per source
5. **Polish window positioning** — Detect actual notch location from screen geometry
