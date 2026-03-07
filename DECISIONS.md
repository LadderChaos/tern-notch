# Architectural Decision Records

## ADR-001: Fork boring.notch instead of standalone app
- **Date**: 2026-03-06
- **Status**: Accepted
- **Context**: Needed a macOS notch HUD for AI coding sessions. Building from scratch would require reimplementing notch rendering, window management, and system integration.
- **Decision**: Fork boring.notch and add Companion feature as a module in `boringNotch/Companion/`.
- **Consequences**: Get all boring.notch features for free (media, calendar, shelf, HUDs). Must maintain compatibility with upstream. Carries upstream dependencies (Sparkle, etc.).

## ADR-002: JSONL file watching for Claude/Codex, SQLite polling for OpenCode
- **Date**: 2026-03-06
- **Status**: Accepted
- **Context**: Claude Code writes JSONL files per session. Codex also uses JSONL. OpenCode uses SQLite.
- **Decision**: Use DispatchSource file watchers for JSONL (real-time). Poll SQLite every 2s for OpenCode (can't watch SQLite reliably with file events).
- **Consequences**: Claude/Codex updates are instant. OpenCode has up to 2s latency. Polling is less efficient but simple and reliable.

## ADR-003: Agent-colored effects instead of uniform color
- **Date**: 2026-03-07
- **Status**: Accepted
- **Context**: Multiple agent types (Claude, Codex, OpenCode) can run simultaneously. Need visual distinction.
- **Decision**: Card backgrounds at 4% opacity (orange/green/blue). Flowing light (流光) uses agent color. Removed grey activity glow due to clipping issues.
- **Consequences**: Easy to identify which agent is which at a glance. Color scheme is consistent across cards and effects.

## ADR-004: Rename to notchHUD
- **Date**: 2026-03-07
- **Status**: Accepted
- **Context**: "Notch Companion" was generic and didn't convey the HUD nature of the app.
- **Decision**: Rename to "notchHUD" — app name, repo, folder, all references.
- **Consequences**: GitHub repo URL changed. Old links broken (GitHub auto-redirects). Clearer branding.
