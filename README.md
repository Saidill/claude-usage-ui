# Claude Usage

A small macOS menu bar app that keeps an eye on Claude Code for you, and gets you back to work faster.

The popover has three tabs:

- **Now**: your session (5-hour) and weekly plan limits, and every running Claude Code session. **Click a session to jump to it**: its Terminal or iTerm2 tab comes to the front, or its VS Code / Cursor window.
- **Recent**: your last conversations, titled the way Claude Code titles them. **Click one to resume it** in a new Terminal window (`claude --resume`).
- **Usage**: tokens today and over the last 7 days, by hour, by model, and split into input, output and cache.

And in the background:

- **A sound when Claude finishes**, plus a notification, so you can look away while it works.
- **Limit alerts**: a heads-up when your session or weekly limit passes 80% (adjustable), and a ping the moment your session limit resets.

The menu bar icon is a small ring that fills up as you use your session limit. It shows a "working" ring while Claude is busy and a check mark when a session finishes.

It's built to stay light: nothing animates unless something changes, past sessions are only read when you open the Recent tab, and token counts refresh every 15 seconds (and whenever you open the popover).

## Requirements

- macOS 14 or later (built and tested on an M2 MacBook)
- [Claude Code](https://claude.com/claude-code), logged in with a Claude subscription
- Xcode Command Line Tools (`xcode-select --install`)

## Install

```bash
git clone https://github.com/<your-username>/claude-usage-ui.git
cd claude-usage-ui
./scripts/build-app.sh
cp -R ClaudeUsage.app /Applications/
open /Applications/ClaudeUsage.app
```

Then click the ring in the menu bar → ⚙ → turn on **Open at login**. From then on it starts by itself.

If you change the code later, run `./scripts/build-app.sh` again and copy the new app into `/Applications`.

## How it works

Everything is read from files Claude Code already writes on your Mac. Nothing is sent anywhere, apart from one request for your plan limits.

| What | Where it comes from |
| --- | --- |
| Sessions and the finish sound | `~/.claude/sessions/*.json`. Each running session has a `status`, and a change from `busy` to anything else means Claude finished. Checked every second. |
| Token counts | `~/.claude/projects/**/*.jsonl` transcripts. Only new lines are read, every 2 seconds. |
| Plan limits and alerts | `GET https://api.anthropic.com/api/oauth/usage`, using the login token Claude Code keeps in your Keychain. Refreshed every minute. |
| Recent sessions | The newest transcripts in `~/.claude/projects`. Only the last 64 KB of each file is read, for its title and folder. |
| Jump to session | Finds the app that owns the session's process. For Terminal and iTerm2 it selects the tab by its TTY using AppleScript; macOS asks once for permission. |

The plan-limits endpoint is **unofficial**: it's the same one Claude Code's `/usage` command uses, and Anthropic may change it. If it stops working, the app says so and everything else keeps working.

Token counts cover Claude Code only, not chats on claude.ai or the Claude desktop app.

## Project layout

```
Sources/ClaudeUsage/
  ClaudeUsageApp.swift     app entry point and menu bar icon
  SessionMonitor.swift     watches running sessions and detects when one finishes
  UsageTracker.swift       reads transcripts and adds up tokens
  PlanLimitClient.swift    fetches plan limits
  Notifier.swift           finish sound and notifications
  RecentSessions.swift     past sessions for the Recent tab
  TerminalLauncher.swift   jump to a session's terminal, resume a past session
  Views/                   popover, settings, colours and animated components
scripts/build-app.sh       builds ClaudeUsage.app
```

## Development

```bash
swift build                 # compile
./scripts/build-app.sh      # build the .app bundle
```

No Xcode project is needed. It's a plain Swift package.
