# Changelog

## [Unreleased]

### Added
- Multi-agent session monitoring: Claude Code, Codex, and OpenCode
- OpenCode support via SQLite polling (`~/.local/share/opencode/opencode.db`)
- Codex support via JSONL file watching (`~/.codex/sessions/`)
- Swipeable paginated session cards (2 per page, horizontal scroll)
- Agent-colored card backgrounds (orange=Claude, green=OpenCode, blue=Codex)
- Agent-colored flowing light (流光) effect on notch border when permission needed
- Translucent frosted glass notch background when open
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
- `<synthetic>` model name filtered from Claude JSONL parsing
- OpenCode timestamp comparison (milliseconds vs seconds)
- Context usage no longer jumps/sticks at 100%

### Removed
- NotchActivityGlow (grey idle glow) — had persistent clipping issues
- "Check for Updates" button from About page
- "Release name" row from About page
