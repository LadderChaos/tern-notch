# Changelog

## [Unreleased]

### Added
- Standalone Tern Notch app with a live ternwatch NDJSON stream, drawn as a black notch silhouette attached to the camera housing at the physical screen top (a matching notch over the menu bar on displays without one). It has no menu bar or Dock icon: quit with the power button in the open notch's header, or Cmd-Q while the notch has keyboard focus
- Symmetric collapsed notch: one agent in each wing at all times (the shown conversation's pair, otherwise the first two working or idle agents, with a crew avatar filling an empty wing), each over a soft glow in its color. A hairline along the bottom edge joins the pair's colors; a fresh message runs along it as a comet from sender to recipient while their glows swell
- Hover to open: after a short dwell the notch unfolds without activating the app or taking keyboard focus, then folds about half a second after the pointer leaves. A click inside (needed to type in the composer) pins it and gives it focus. Clicking the collapsed notch opens it pinned
- Expanded notch (about 820 × 520 points, limited to the screen) laid out as two agents in conversation: a mirrored header with each agent's face, name, and reported intent, joined by a line a comet crosses from sender to recipient when a new message arrives; below it a mirrored transcript, oldest first, that scrolls to new messages, with the left agent's bubbles on the left and the right agent's on the right, each in its color
- Conversation switcher strip: one chip per recent agent pair (both faces, names, and message count, newest first; new messages make it glow briefly). Click a chip to pin that conversation in both notch states, or **Live** to follow the latest. The agent who sent the first loaded message stays on the left
- **Subagents** switch in the open header, off by default and kept between launches. Off: conversations are between top-level panes only. On: subagents take part on their own, each in a color derived from a stable hash of its name and always different from its parent's. With no conversations left, the empty state says how many subagent messages are hidden
- Agent faces show only reported state: awake and occasionally blinking or wiggling the antenna while working, tilting the antenna and glancing aside while waiting on subagents, eyes closed while idle, a crossed-out bot when closed; the sender hops and the recipient's eyes widen while a fresh message travels
- Agent detail (click a face in the conversation header) with Focus, Copy pane ID, the agent's exchanges, and a composer; message detail (click a bubble) with the full text, Copy, and jumps to the sender or recipient; Esc steps back from message to agent to pinned conversation, then folds the notch
- **Message** picker in the conversation strip opens any available agent's composer, including agents with no conversation; selecting an agent focuses the message field, and closed panes are disabled
- Comets and glows run only for newly observed traffic, never for loaded history or delivery updates, stop when nothing is arriving, and turn off with Reduce Motion
- Per-session context window size (258k for Codex, 200k default)
- Agent-colored dots in the collapsed notch view
- Distinct permission-mode badge colors (YOLO=green, Auto=cyan, Plan=purple, Ask=white)

### Fixed
- Opening and closing keep the hosting canvas at a fixed size, centered at the screen top, so the window resize does not move the collapsed content before it unfolds
- Collapsed agent icons sit next to the camera with clear space before the wing's outer curve
- Crash after opening and folding the notch ("more Update Constraints in Window passes than there are views"): the SwiftUI hosting view now sits inside a plain container and ignores safe areas, so it can no longer resize the window from layout
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
