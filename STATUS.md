# notchHUD — Project Status

## Current Focus
v0.1.0 released. Polishing glow effects and preparing for wider distribution.

## Recent Changes (2026-03-08)
- Codex integration fixed (`ab8fb8c`): JSONL parser now unwraps `payload` and reads `session_meta`, `event_msg`, `response_item`, `turn_context`
- Codex project name from `cwd` (was the day directory, e.g. "07"); git branch from `session_meta.payload.git.branch`
- Codex permission detection (pending tools + timeout timer)
- Token display per-turn (`last_token_usage`) instead of cumulative; per-session context window (258k Codex, 200k default)
- Codex model name parsed from `turn_context` (`gpt-5.4` → "5.4"); readable tool arguments (`cmd`, `file_path`, `pattern`)
- Initial JSONL read buffer 8 KB → 32 KB (Codex `session_meta` ~15 KB)
- Agent colors standardized for agent identity indicators (card, glow, collapsed-view dots): Claude=orange, Codex=green, OpenCode=blue; dots added to collapsed view
- Badge colors follow mode, not agent (YOLO=green, Auto=cyan, Plan=purple, Ask=white; model badge white)
- Docs corrected: ADR-003 now states the concrete mapping; CHANGELOG 0.1.0 entry had Codex/OpenCode swapped

## Recent Changes (2026-03-07)
- Apple Intelligence-style glow effect (layered strokes, randomized gradient stops, easing animation)
- Closed notch: animated glow when permission needed
- Open notch: static agent-colored border on session card needing permission
- Fixed closed notch sizing (CompanionCompactView was 20pt too wide)
- Fixed open/close animation flash (black base layer always present under translucent background)
- Added 6pt horizontal padding to session cards for border visibility
- README: install instructions (Download + Build from Source), xattr note for Sequoia
- Screenshot added to README
- First GitHub Release: v0.1.0
- Security audit: clean, fixed hardcoded username in code comment
- Added .mcp_data/ to .gitignore

## Prior Session Highlights
- Multi-agent support: Claude (JSONL file watching), Codex (JSONL), OpenCode (SQLite polling)
- Swipeable paginated session cards (2 per page)
- Agent-colored card backgrounds (orange/green/blue at 4% opacity)
- Translucent notch when open (VisualEffectView + black overlay)
- Rebrand from "Notch Companion" to "notchHUD"
- New app icon (concentric orange rings on dark background)

## Pending / Next Steps
- Consider changing bundle identifier from `theboringteam.boringnotch` to avoid config conflicts with boring.notch
- App icon not showing in Settings → Advanced (upstream "Coming soon" limitation)
- Consider removing boring.notch-specific settings that don't apply
- Clean up debug logging code
- OpenCode polling latency (2s vs real-time)
- Add more screenshots to README (closed notch, glow effect)
- Consider app notarization for easier distribution

## Known Issues
- OpenCode polling-based (not real-time like Claude JSONL file watching)
- Sandbox container paths differ from `/tmp/` — debug logs go to `~/Library/Containers/theboringteam.boringnotch/Data/tmp/`
- Bundle ID shared with boring.notch (can't run both simultaneously)

## Architecture
```
boringNotch/Companion/
  ClaudeCodeModels.swift    — Session, state, token, tool, and todo models
  CompanionManager.swift    — File-watching session discovery and JSONL/SQLite parsing
  CompanionView.swift       — Expanded session cards (two-up, paginated)
  CompanionLiveActivity.swift — Compact collapsed view in the notch
  NotchGlowEffect.swift     — Apple Intelligence-style glow + card border effects
```
