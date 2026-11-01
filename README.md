# Tern Notch

Tern Notch is a small macOS menu bar app for monitoring and directing Tern agents. It extends the camera notch with a black surface. When collapsed, it adds a wing on each side of the camera. The left wing shows one animated bar per working agent, in that agent's color. The right wing shows the working and open agent counts and briefly flashes `+N` when new orchestration messages arrive. Click the notch to unfold it from the top edge of the screen into a compact surface, about 760 × 440 points and limited to the screen. Click the header, press Esc at the overview, or click another app to fold it back. The menu bar icon also opens or closes the notch and provides Quit. The stream keeps running while the notch is collapsed.

The open notch has two columns. The left column lists agents. Working agents come first, including orchestrators waiting on running subagents. Each shows its tool and intent, task progress, and subagents. Idle and closed agents are grouped under a collapsible **Idle** row. The right column lists recent orchestration exchanges, newest first. Each has a colored sender and recipient, a delivery state, and a two-line preview.

## Requirements

- macOS 14 or later and Xcode 15 or later to build.
- Tern and its `tern` command-line executable.
- A current `ternwatch` executable with `--json --follow` support.

Build and install ternwatch from a checkout containing the `--follow` change:

```sh
cd /path/to/ternwatch
cargo install --path . --force
```

Click an agent to see its details, its exchanges, and a message composer. Click an exchange to read the full message, copy it, or jump to the sender or recipient. Use the back button or Esc to step back from a message to its agent, then to the overview, then to fold the notch. Focus opens the selected pane in Tern. Send runs `tern run` with the composed text, which types it and presses Enter in that pane. Delivery states report what the transcripts show, not proof that a recipient acted on a message. Your selection and draft are kept while the notch is collapsed.

Working agents have a breathing halo. A newly observed message travels as a comet in its sender's color, from the sender's dot to the recipient's dot. When the recipient is hidden in the collapsed Idle group, the comet ends at that group's row. Each arrival ends in a ripple. The new exchange slides in at the top of the list and glows briefly. Only messages sent in the last few seconds animate, and only after the first snapshot. Loaded history, reconnects, and delivery-state updates never animate. Animations pause when nothing is working or arriving, and Reduce Motion turns them off.

The app looks for these executables on its inherited `PATH`, plus `~/.local/bin`, `~/.cargo/bin`, `/opt/homebrew/bin`, and `/usr/local/bin`. It also checks `/Applications/Tern.app/Contents/MacOS/tern`. You can set `TERNWATCH_BIN` and `TERN_BIN` to executable paths in the Xcode scheme's Run environment or in the environment used to launch the app. A graphical app does not necessarily inherit your shell's PATH.

## Build and run

Open `boringNotch.xcodeproj` in Xcode, select the `TernNotch` target, and run it. If signing requires configuration, select your development team in the target's Signing & Capabilities settings. The project has no third-party package dependencies. The app is unsandboxed so it can launch the local Tern tools.

On a notched display, the collapsed surface is exactly as tall as the camera housing and centered on it. On other displays, a matching notch is drawn over the center of the menu bar. Connection errors appear as a banner with Copy and Restart buttons. The header's refresh button restarts `ternwatch` after you install or update it. The app also retries a stopped or missing stream automatically. To quit, use the Tern Notch menu bar icon.
