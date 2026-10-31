# Changelog

## [Unreleased]

### Added
- Per-session context window size (258k for Codex, 200k default)
- Agent-colored dots in the collapsed notch view
- Distinct permission-mode badge colors (YOLO=green, Auto=cyan, Plan=purple, Ask=white)

### Fixed
- Codex JSONL parser read top-level keys instead of unwrapping `payload`; now parses `session_meta`, `event_msg`, `response_item`, and `turn_context`
- Codex project name showed the day directory ("07"); it now comes from `cwd`
- Codex git branch now read from `session_meta.payload.git.branch`
- Codex permission detection via pending tools plus a timeout timer
- Codex token counts showed cumulative totals; now per-turn `last_token_usage`
- Codex model name now parsed from `turn_context` (`gpt-5.4` → "5.4")
- Tool arguments now show readable values (`cmd`, `file_path`, `pattern`) instead of raw JSON
- Initial JSONL read buffer raised from 8 KB to 32 KB (Codex `session_meta` is ~15 KB)
- Agent colors consistent on every surface: Codex=green, OpenCode=blue

## [0.1.0] - 2026-03-07

### Added
- Multi-agent session monitoring: Claude Code, Codex, and OpenCode
- OpenCode support via SQLite polling (`~/.local/share/opencode/opencode.db`)
- Codex support via JSONL file watching (`~/.codex/sessions/`)
- Swipeable paginated session cards (2 per page, horizontal scroll)
- Agent-colored card backgrounds (orange=Claude, green=Codex, blue=OpenCode)
- Apple Intelligence-style glow effect on closed notch when permission needed
- Static agent-colored border on session card when open and needs permission
- Translucent frosted glass notch background when open (black base layer for smooth animation)
- Screenshot in README
- Installation instructions (Download from Releases + Build from Source)
- First GitHub Release (v0.1.0)
- Git branch display for all agent types
- Token usage tracking (input/output/cache) with context window percentage bar
- Todo progress tracking per session
- Permission mode badges (YOLO, Auto, Ask, Plan)
- Model display with smart abbreviation (Opus, Sonnet, Haiku, etc.)
- New app icon (concentric orange rings on dark background)
- About page with notchHUD description and boring.notch acknowledgement
- Sandbox entitlements for `~/.claude/`, `~/.codex/`, `~/.local/share/opencode/`

### Changed
- Renamed app from "boring.notch" to "notchHUD"
- Renamed GitHub repo to `LadderChaos/notchhud`
- About page: removed Sparkle update checker, added dual GitHub links
- Context percentage now uses per-message tokens (not cumulative sum)

### Fixed
- Closed notch sizing (CompanionCompactView was 20pt wider than physical notch)
- Open/close animation flash caused by instant background switch to translucent
- `<synthetic>` model name filtered from Claude JSONL parsing
- OpenCode timestamp comparison (milliseconds vs seconds)
- Context usage no longer jumps/sticks at 100%
- Hardcoded username removed from code comment

### Removed
- NotchActivityGlow (grey idle glow) — had persistent clipping issues
- "Check for Updates" button from About page
- "Release name" row from About page
