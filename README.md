# Agents Usage Watch

**Your coding agents' plan limits, in the macOS menu bar and on your desktop.**

Agents Usage Watch shows how much of your 5-hour and weekly limits you've used in Claude Code, OpenAI Codex
and the Antigravity CLI, plus what opencode spent today. It covers every login side by side, with reset
countdowns, a pace marker and a forecast of where the week will end. It reads only files the agents already
write on your Mac. It doesn't log in anywhere, makes no network requests for your usage, and has no
analytics.

Free and open source under the [MIT License](LICENSE). Made by [AgentsTrack](https://agentstrack.ai).

## Features

- **Menu bar:** your highest usage at a glance. The panel lists every account with its weekly bar, the
  5-hour bar where the plan has one, a pace tick (where you'd be if you used the week evenly), the trend
  (`+3.9%/day`), a projection (`on track for 52%` / `runs out before reset`) and a chart of the week or the
  last 4 weeks.
- **Widgets:**
  - **Usage** comes in small, medium and large. With many accounts it switches to denser rows, so every
    account stays visible. The small widget has a switcher that steps through your accounts.
  - **Usage Progress** comes in small, medium and large and shows the weekly % over time, one line per
    account.
  - Right-click › Edit Widget to pick accounts, a background (standard, transparent or tinted), and whether
    to show the pace marker and trend. Click a widget to refresh.
- **Notifications:**
  - **Thresholds:** 5-hour and weekly, sent once per window.
  - **Forecasts:** "may run out before reset", "on track to leave most of it unused" (mid-week), and
    "burning much faster than usual" (after a few days of history).
  - **Delivery:** quiet hours, a choice of sound (or none), and a test button that tells you if macOS is
    blocking notifications. Urgent alerts are marked Time Sensitive when the app is signed with that
    entitlement.
- **Accounts:** finds them on its own. Rename, hide, reorder, and choose which ones appear in the menu and in
  widgets.

Requires macOS 14 Sonoma or later.

## Supported agents

| Agent | What it shows | Where it comes from |
|---|---|---|
| **Claude Code** | 5-hour and weekly limits, plan | Claude Code's status line JSON (`rate_limits`), saved by a small helper script after each message. Works for `~/.claude` and every folder you use with `CLAUDE_CONFIG_DIR`. |
| **OpenAI Codex CLI** | 5-hour and weekly limits, plan | The `rate_limits` Codex writes into its own session logs (`~/.codex/sessions`). |
| **Antigravity CLI** (`agy`) | 5-hour and weekly limits for Gemini and third-party models | The `quota` in agy's status line JSON, saved by a helper script. |
| **opencode** | Tokens and cost today and over 7 days (it has no plan limit) | opencode's own SQLite database, opened read-only. |

Values are as fresh as the agent's last message. After two hours without one, an account shows its last
values with "Last used" and the time. A window whose reset time has passed shows as empty until the agent
reports again.

## Install

There's no signed download yet, so you build it yourself. It takes a couple of minutes.

You need Xcode 15 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/agentstrack/agents-usage-watch.git
cd agents-usage-watch
cp Config/Local.xcconfig.example Config/Local.xcconfig   # set your team ID and a bundle ID prefix
./install.sh                                              # builds, installs to ~/Applications and starts it
```

- **Signing:** the widget needs a signing team for its app group. A free Apple ID team is enough. Find your
  team ID in Xcode › Settings › Accounts.
- **Starting at login:** the app adds itself as a login item on first launch. Turn that off in Settings ›
  General.
- **Adding the widgets:** right-click the desktop › Edit Widgets › Agents Usage Watch.

### Setting up Claude Code and Antigravity

Open **Settings › Accounts** and click **Set Up** next to the account.

1. The app backs up that agent's `settings.json` once (`settings.json.agentsusagewatch-backup`).
2. It then points `statusLine.command` at a helper script in `~/.agentsusagewatch/`.
3. After each message, the helper saves only the limits part of the status JSON. It then runs the status
   line command you had before with the same input, so your status line looks the same as it did.

**Remove** puts your previous command back. The helpers are plain shell scripts that use only macOS tools
(`plutil`, `shasum`). Read them in [`App/Resources/`](App/Resources).

Codex and opencode need no setup.

## Privacy

- **No network for your usage:** the app reads the agents' own local files and makes no network requests to
  get it.
- **No logins:** it doesn't log in to anything or use your credentials. For Codex it opens `~/.codex/auth.json`
  only to check that you're logged in and to show the account email.
- **No analytics:** nothing about you or your usage leaves your Mac.
- **What it stores:** your usage history (weekly % per account, 35 days) in
  `~/Library/Application Support/AgentsUsageWatch/`. The widget, which runs sandboxed, only reads a snapshot
  that the app writes to a shared app-group container.

## Development

```sh
./install.sh                     # build, install, restart
log stream --predicate 'subsystem == "<your bundle prefix>.agentsusagewatch"'   # watch it work
```

The logic checks cover parsers, the helper scripts end to end, alert rules and the maths. They run without
Xcode, and CI runs them on every push:

```sh
swiftc -o /tmp/chk Shared/Model.swift App/Parse.swift App/Alerts.swift App/Accounts.swift \
  App/StatusLine.swift Checks/ModelCheck/main.swift && /tmp/chk
```

`./install.sh --testing` builds a private variant with a second, token-based Claude source, meant only for
the maintainer's own machine. Its code is compiled out of the normal build.

| Path | What |
|---|---|
| `App/` | Menu bar app: agent readers (`Accounts`, `StatusLine`, `Parse`), alert rules (`Alerts`), state (`Store`), panel and Settings UI |
| `App/Resources/` | The status line helpers the app installs on Set Up |
| `Widget/` | WidgetKit extension: timelines, widget settings, refresh and account-switch intents |
| `Shared/` | Snapshot model and views used by both the app and the widgets |
| `Checks/` | Fixture-based checks for the pure logic |
| `Tools/make-icon.swift` | Draws the app icon |

Adding another agent means writing a reader that returns its windows (see `Codex` in `App/Accounts.swift`),
plus a fixture check. Contributions are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE): free to use, change and share, including commercially.

Not affiliated with Anthropic, OpenAI, Google or the opencode project. Product names appear only to say
which tools are supported.
