# Claude Companion

A macOS notch companion app for **Claude Code** and **OpenAI Codex** — real-time visibility into your AI coding assistants, right in the MacBook notch.

Inspired by [boringnotch](https://github.com/TheBoredTeam/boring.notch) and [AgentNotch](https://github.com/AppGram/agentnotch).

## Features

- **4-Phase Pipeline** — Researching → Reasoning → Writing → Reviewing, each with colored progress bars
- **Multi-Agent Support** — Claude Code (orange indicator) and Codex (blue indicator) with automatic source detection
- **Tool Call Tracking** — See every tool call (web_search, code_exec, file_read) with counts and recency
- **Live Metrics** — Token usage, latency, and model info updated in real-time
- **Notch-Native** — Floats below the MacBook notch, zero screen real estate used
- **OTLP Telemetry** — Receives telemetry via OpenTelemetry protocol (logs, metrics, traces)

## Screenshots

The companion shows a stacked phase pipeline. Tap any phase to expand the detail panel with tool calls and metrics:

```
┌──────────────────────────────────────────┐
│ 🔍 Researching  ━━━━━━━━━━━━━━━━━  1/4  │
├──────────────────────────────────────────┤
│ 💬 Reasoning    ━━━━━━━━━━━━━━━━━  2/4  │
│ ┌────────────────────────────────────┐   │
│ │  🔍 Researching  💬 Reasoning     │   │
│ │  ✏️ Writing      ⚙️ Reviewing     │   │
│ │                                    │   │
│ │  Tool Calls                        │   │
│ │  web_search         x3  2s ago     │   │
│ │  code_exec          x1  8s ago     │   │
│ │  file_read          x5  just now   │   │
│ │                                    │   │
│ │  Tokens    Latency    Model        │   │
│ │  19.800    143ms      Opus 4.6     │   │
│ └────────────────────────────────────┘   │
├──────────────────────────────────────────┤
│ ✏️ Writing      ━━━━━━━━━━━━━━━━━  3/4  │
├──────────────────────────────────────────┤
│ ⚙️ Reviewing    ━━━━━━━━━━━━━━━━━  4/4  │
└──────────────────────────────────────────┘
```

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ (to build from source)
- MacBook with notch (works on any Mac, but designed for notch)

## Setup

### 1. Build & Run

```bash
cd apps/companion/ClaudeCompanion
swift build
swift run
```

Or open in Xcode:
```bash
open ClaudeCompanion/Package.swift
```

### 2. Connect Your AI Agent

Set the OTLP endpoint before starting your coding agent:

```bash
# For Claude Code
export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4318"
claude

# For Codex
export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4318"
codex
```

The companion auto-detects the source from OTLP resource attributes (service name, model name) and shows the appropriate indicator color:
- **Orange** — Claude Code
- **Blue** — OpenAI Codex
- **Light blue** — Unknown agent

### 3. Menu Bar

Click the brain icon (🧠) in the menu bar to:
- Toggle companion visibility
- Load demo data
- Reset session

## Architecture

```
Sources/
├── App/
│   ├── ClaudeCompanionApp.swift   # @main entry point
│   ├── AppDelegate.swift          # Menu bar + window lifecycle
│   └── NotchWindow.swift          # NSPanel positioned at notch
├── Models/
│   ├── AgentSource.swift          # Claude / Codex source detection
│   ├── Phase.swift                # 4 phases with colors/icons
│   ├── ToolCall.swift             # Tool call categories
│   └── SessionMetrics.swift       # Tokens, latency, model, source
├── Views/
│   ├── CompanionNotchView.swift   # Main view (phase pipeline)
│   ├── PhasePillView.swift        # Collapsed phase pill
│   ├── PhaseTabBar.swift          # Tab bar in detail panel
│   ├── DetailPanelView.swift      # Expanded detail panel
│   ├── ToolCallsView.swift        # Tool call list
│   ├── MetricsBar.swift           # Bottom metrics display
│   └── SourceIndicator.swift     # Agent source dot + badge
├── ViewModels/
│   └── CompanionViewModel.swift   # State management + telemetry binding
├── Telemetry/
│   └── OTLPReceiver.swift         # HTTP server for OTLP/HTTP
└── Theme/
    └── CompanionTheme.swift       # Colors, spacing, animations
```

## Phase Colors

| Phase | Color | Hex |
|-------|-------|-----|
| Researching | Purple | `#7359D9` |
| Reasoning | Pink | `#E6408C` |
| Writing | Cyan | `#00D9D9` |
| Reviewing | Orange/Amber | `#E6A626` |

## License

MIT
