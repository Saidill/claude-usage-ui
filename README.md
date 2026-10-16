# Claude Usage

A small macOS menu bar app that keeps an eye on Claude Code for you, and gets you back to work faster.

The popover has three tabs:

- **Now**: your session (5-hour) and weekly plan limits, and every running Claude Code session. **Click a session to jump to it**: its Terminal or iTerm2 tab comes to the front, or its VS Code / Cursor window.
- **Recent**: your last conversations, titled the way Claude Code titles them. **Click one to resume it** in a new Terminal window (`claude --resume`).
- **Usage**: tokens today and over the last 7 days, by hour, by model, and split into input, output and cache.

It has two display modes. Switch with the button in the header, or in Settings → Display:

- **Menu bar**: the popover above, for when you work on an external monitor.
- **Notch**: on a MacBook screen, the app lives in the camera notch instead. While Claude works, the notch widens a little, with a breathing dot on one side and your session limit on the other. When a prompt finishes, a card drops out of the notch with a **Jump** button. Hover the notch to open the whole app.
- **Auto** (the default) uses the notch while the laptop screen is your only screen and switches to the menu bar as soon as you plug in a monitor. No restart needed.

And in the background:

- **A sound when Claude finishes**, plus a notification, so you can look away while it works.
- **Limit alerts**: a heads-up when your session or weekly limit passes 80% (adjustable), and a ping the moment your session limit resets.
- **Limit forecast**: under the Session bar, where you're heading at your current pace ("At this pace, full at 3:40 PM" or "On pace to last until the reset"), worked out from the last 30 minutes. If you're on track to hit the limit within half an hour, you get a heads-up.

The popover is black frosted glass with silver accents, whatever your system appearance, and everything moves with the same calm, smooth curves. A gunmetal dragon with silver horns and a glowing amber eye watches over things in the header, the notch and the "finished" card: it sleeps with smoke curling from its nostril when nothing is running, growls with embers in its jaw while Claude works, and rears back and roars fire when a prompt finishes. Click it to make it roar. Quit is in Settings → System. The menu bar icon is a small ring that fills up as you use your session limit. It shows a "working" ring while Claude is busy and a check mark when a session finishes.

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

If you change the code later, run `./scripts/build-app.sh --install`. It rebuilds the app, replaces the copy in `/Applications` and relaunches it.

While you're working on it, run `./scripts/dev.sh` and leave it open: every time you save a file in `Sources/`, the app rebuilds and relaunches by itself, so you never have to quit and reopen it.

To check that everything still works after a change, run the self-test. It switches between the menu bar and the notch several times, opens and closes each one, checks that they respond, and saves a picture of every screen plus a `report.txt` to the folder you give it:

```bash
./scripts/build-app.sh && ./ClaudeUsage.app/Contents/MacOS/ClaudeUsage --selftest /tmp/claude-usage-test
```

## How it works

Everything is read from files Claude Code already writes on your Mac. Nothing is sent anywhere, apart from one request for your plan limits.

| What | Where it comes from |
| --- | --- |
| Sessions and the finish sound | `~/.claude/sessions/*.json`. Each running session has a `status`, and a change from `busy` to anything else means Claude finished. Checked every second. |
| Token counts | `~/.claude/projects/**/*.jsonl` transcripts. Only new lines are read, every 2 seconds. |
| Plan limits and alerts | `GET https://api.anthropic.com/api/oauth/usage`, using the login token Claude Code keeps in your Keychain. Refreshed every minute and when you open the popover. When the token expires (after about 8 hours without Claude Code running), the app renews it and saves it back, so Claude Code stays logged in. |
| Recent sessions | The newest transcripts in `~/.claude/projects`. Only the last 64 KB of each file is read, for its title and folder. |
| Jump to session | Finds the app that owns the session's process. For Terminal and iTerm2 it selects the tab by its TTY using AppleScript; macOS asks once for permission. |

The plan-limits endpoint is **unofficial**: it's the same one Claude Code's `/usage` command uses, and Anthropic may change it. If it stops working, the app says so and everything else keeps working.

The Session and Week limits are shared, so they include your chats on claude.ai and in the Claude desktop app. Token counts cover Claude Code only, because chats aren't saved on your Mac.

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
