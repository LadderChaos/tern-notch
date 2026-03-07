# notchHUD — Project Status

## Current Focus
Polishing UI, branding, and settings for the notchHUD fork of boring.notch.

## Recent Changes (This Session — 2026-03-07)
- Renamed app from "Notch Companion" to "notchHUD" (pbxproj, Info.plist, README, debug logs)
- Renamed GitHub repo from `notch-companion` to `notchhud` (LadderChaos/notchhud)
- Renamed local folder from `notch-companion` to `notchhud`
- New app icon (concentric orange rings on dark background) — all sizes 16-1024px
- NotchFlowingLight (流光) now accepts color param, varies by agent type (orange=Claude, green=OpenCode, blue=Codex)
- Removed NotchActivityGlow from closed notch (was too buggy with clipping)
- Updated About page: removed Sparkle updater UI, added notchHUD description, boring.notch acknowledgement, dual GitHub links
- Removed "Release name" row from About
- Card gap kept at 4pt between session cards

## Prior Session Highlights
- Multi-agent support: Claude (JSONL file watching), Codex (JSONL), OpenCode (SQLite polling)
- Swipeable paginated session cards (2 per page)
- Agent-colored card backgrounds (orange/green/blue at 4% opacity)
- Translucent notch when open (VisualEffectView + black overlay)
- OpenCode: activity detection, git branch, model/mode display, token tracking
- Context percentage uses latest message tokens (not cumulative sum)
- Filtered `<synthetic>` model from Claude JSONL

## Pending / Next Steps
- Commit and push all uncommitted changes (19 files changed)
- App icon not showing in Settings → Advanced → "App icon" section (that section is disabled/"Coming soon" from upstream)
- Consider removing boring.notch-specific settings that don't apply (Downloads, some HUD options)
- Clean up debug logging code (debugLog helper, NSLog/print statements)
- The `NotchCompanion/` directory in git status (from early iteration) — already deleted

## Known Issues
- NotchActivityGlow had clipping issues (glow not showing on bottom/sides) — removed for now
- OpenCode polling-based (not real-time like Claude JSONL file watching)
- Sandbox container paths differ from `/tmp/` — debug logs go to `~/Library/Containers/theboringteam.boringnotch/Data/tmp/`

## Architecture
```
boringNotch/Companion/
  ClaudeCodeModels.swift    — Session, state, token, tool, and todo models
  CompanionManager.swift    — File-watching session discovery and JSONL/SQLite parsing
  CompanionView.swift       — Expanded session cards (two-up, paginated)
  CompanionLiveActivity.swift — Compact collapsed view in the notch
  NotchGlowEffect.swift     — Permission flowing light effect (流光)
```

Integration points in boring.notch (~17 lines of glue code):
- `enums/generic.swift` — added `claudeCode` view case
- `models/Constants.swift` — added settings keys
- `boringNotchApp.swift` — CompanionManager initialization
- `ContentView.swift` — companion views in closed/open states, translucent background, glow overlay
