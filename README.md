# CC Permission Center

A macOS menu-bar app that centralizes Claude Code's permission prompts and notifications across multiple parallel sessions. Instead of hunting through terminal tabs to find which Claude is asking for permission, you get a single popup near the top of the screen with global keyboard shortcuts.

## What it does

- **Permission prompts** — When Claude wants to run `Bash`, `Edit`, `Write`, `WebFetch`, an MCP tool, or read a file outside the project, a banner appears at the top-center of your active screen with the project name, terminal, tool name, and a clean diff (for file edits) or `$ command` view (for Bash). Three actions: **Accept**, **Reject**, **Jump to terminal**.
- **Global hotkeys** — `⌃⌥A` accept, `⌃⌥R` reject, `⌃⌥J` jump. Work from any focused app — you don't need to click the popup.
- **No focus stealing** — The popup floats on top but doesn't take keyboard focus from whatever you're doing.
- **Activity notifications** — Small top-right banners when Claude finishes a turn (`needs your input`), asks via `AskUserQuestion`, or fires other notifications.
- **Already in the terminal? No popup.** — If the originating iTerm tab is the frontmost window, the app stays out of the way and Claude's native prompt handles things in the terminal.
- **Per-tool views**
  - `Bash` — Run command with `$` prefix, multi-line, monospaced.
  - `Edit` / `MultiEdit` — File path + unified line diff with `+`/`-` highlighting.
  - `Write` — File path + new content.
  - `Read` — File path (no JSON noise).
  - `WebFetch` — URL + prompt.
  - Other / MCP — Generic tool name + pretty JSON.
- **Multi-session aware** — Tracks active sessions; only appends a terminal disambiguator (e.g. `iTerm2 · 8e1c2f`) when two sessions share the same project directory.
- **Jump to terminal** — For iTerm2, AppleScript targets the exact tab via `ITERM_SESSION_ID`. For VS Code / Conductor / Ghostty / Warp, brings the main app window forward via `NSRunningApplication.activate`.
- **Prompt queue** — Concurrent prompts queue cleanly. The active popup shows `+N waiting` so you know more are pending.
- **Open at Login** — Toggle in the menu bar.

## Requirements

- macOS 14+ (uses SwiftUI + SMAppService)
- Swift 6 toolchain (Apple's `swift` from Xcode 16+ or Command Line Tools)
- Claude Code installed (`claude` CLI)

## Build & run

```bash
make app
open build/CCPermissionCenter.app
```

That builds both binaries (the menu-bar app and the `ccpc-hook` CLI), bundles them into `build/CCPermissionCenter.app`, and ad-hoc signs.

First launch:
1. Click the bell icon in the menu bar
2. **Install Hooks…** — writes ccpc into `~/.claude/settings.json` (merges with any existing hooks, doesn't clobber your chime sounds etc.)
3. (Optional) **Open at Login** — auto-start with macOS
4. Restart any running Claude sessions so they pick up the new hooks

To uninstall: same menu, **Uninstall Hooks**. Settings restore to original state.

## How it works

```
┌──────────────────────────────────────────────────────────────────────┐
│  CCPermissionCenter.app (menu-bar SwiftUI)                           │
│    • Unix-domain socket: ~/Library/Application Support/              │
│      ch.simk.ccpermissioncenter/ipc.sock                             │
│    • Banner panel (top-center) for permission prompts                │
│    • Banner stack (top-right) for notifications                      │
│    • Global hotkeys via Carbon RegisterEventHotKey                   │
└──────────────────────────────────────────────────────────────────────┘
              ▲
              │ Unix socket (line-delimited JSON)
              │
┌──────────────────────────────────────────────────────────────────────┐
│  ~/.claude/hooks/ccpc-hook  →  symlink to bundled binary             │
│    • Reads Claude's PreToolUse / Notification / Stop JSON on stdin   │
│    • Walks parent processes to identify the terminal                 │
│    • Forwards to the app, waits for a decision                       │
│    • Emits Claude's PreToolUse decision JSON on stdout               │
│    • Silent no-op if the app isn't running (Claude's normal flow     │
│      kicks in — including chime sound, native prompt, etc.)          │
└──────────────────────────────────────────────────────────────────────┘
```

**Permission mode awareness.** The hook reads `permission_mode` from Claude's hook payload. In `default` mode, anything outside the always-safe list (`Glob`/`Grep`/`LS`/`TodoWrite`/`ExitPlanMode`/`WebSearch`/`AskUserQuestion`) goes through the popup. In `acceptEdits` mode, file edits also auto-allow. In `plan`, `auto`, `dontAsk`, or `bypassPermissions`, the hook silently steps aside.

**Fallback behavior.** If the app isn't running when a hook fires, the hook exits cleanly with no output → Claude proceeds with its built-in prompt and sound. You don't have to keep the app running.

## File layout

```
Package.swift
Makefile
Resources/
  Info.plist
  AppIcon.icns
Sources/
  CCPermissionCenter/      — menu-bar app
    App.swift               — @main
    AppDelegate.swift       — menu, routing, install actions
    PromptView.swift        — top-center banner for permission prompts
    PromptController.swift  — panel + global hotkeys + prompt queue
    BannerView.swift        — small notification banner
    BannerController.swift  — top-right stack
    DiffView.swift          — LCS-based file diff
    SocketServer.swift      — Unix-socket IPC
    HookInstaller.swift     — settings.json merge/uninstall
    HotkeyManager.swift     — Carbon global hotkeys
    SessionRegistry.swift   — active-session tracking
    TerminalJumper.swift    — iTerm AppleScript + NSRunningApplication
    TerminalFocus.swift     — "is user looking at the terminal?"
    TranscriptReader.swift  — find Claude's latest text in the JSONL
    IPC.swift               — request/response types
    Models.swift            — PermissionRequest
  ccpc-hook/
    main.swift              — CLI hook bridge
```

## Limitations / known gotchas

- **VS Code / Conductor / Ghostty / Warp**: Jump activates the main app window but can't target a specific integrated-terminal tab — only iTerm2 supports per-tab targeting via AppleScript.
- **AppleScript permission**: First click of Jump to iTerm triggers a macOS prompt to allow `CCPermissionCenter` to control iTerm. Grant it.
- **App location**: If you move the `.app` after installing hooks, click **Re-install Hooks** so the symlink at `~/.claude/hooks/ccpc-hook` updates.
- **No native "Claude asked a question" hook**: there's no Claude Code signal for "the assistant ended its turn with a free-form question". The app uses Stop hook + small banner as the indicator that Claude is waiting on you.
- **First launch is unsigned**: ad-hoc signed only. macOS Gatekeeper may require right-click → Open the first time.

## Config

The intercepted-tool list lives at the top of `Sources/ccpc-hook/main.swift`:

```swift
let alwaysSafe: Set<String> = [
    "Glob", "Grep", "LS", "TodoWrite", "ExitPlanMode", "WebSearch",
    "AskUserQuestion",
]
let acceptEditsSafe: Set<String> = [
    "Edit", "Write", "MultiEdit", "NotebookEdit",
]
```

Anything not in those sets gets a popup. Edit and rebuild to taste.

## Hotkeys

| Action | Hotkey |
| --- | --- |
| Accept | `⌃⌥A` (Control + Option + A) |
| Reject | `⌃⌥R` |
| Jump to terminal | `⌃⌥J` |

Hotkeys are only active while a permission popup is visible.
