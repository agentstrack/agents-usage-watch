# AgentsUsageWatch

A macOS menu bar app and desktop widget that shows the plan limits your coding agents report: for Claude Code,
the weekly window and, on plans that have one, the 5-hour window, for one or several logins side by side.
A free tool from [AgentsTrack](https://agentstrack.ai).

- **Menu bar:** highest usage at a glance; the panel shows every account with reset countdowns, a weekly pace
  marker, a trend (+x%/day) and a projection ("on track for 62%" / "runs out before reset").
- **Widgets:** small, medium and large. Pick accounts and background (standard, transparent, tinted) with
  right-click › Edit Widget. Tap to refresh; the large widget has a refresh button.
- **Notifications:** 5-hour and weekly thresholds, "may run out before reset", a mid-week "on track to leave
  most of it unused", and "burning much faster than usual" (after a few days of history). Quiet hours.
- **Accounts:** finds `~/.claude` and every `~/.claude-*` folder you use with `CLAUDE_CONFIG_DIR`, and you can add
  any other folder. Rename, hide and reorder them in Settings.

Requires macOS 14 or later. Not affiliated with Anthropic; "Claude Code" is named only to say which tool is
supported.

## How it works

Claude Code sends a JSON status to its status line
command after each message, and that status includes your current limit percentages (`rate_limits`). The app
reads those numbers; it never logs in anywhere and makes no network requests for them.

1. In **Settings › Accounts**, click **Set Up** next to an account. The app backs up that account's
   `settings.json` once (`settings.json.agentsusagewatch-backup`) and points `statusLine.command` at a small helper
   script, `~/.agentsusagewatch/statusline`. **Remove** puts your previous command back.
2. After each Claude Code message the helper saves only the `rate_limits` part to
   `~/.agentsusagewatch/claude/<key>.json` (key = first 16 hex chars of sha256 of the config folder path), then runs
   your previous status line command with the same input, so your status line looks the same. It uses only macOS
   tools (`plutil`, `shasum`), no `jq`.
3. The app reads those files every 30 s – 15 min (5 min by default). Values are as fresh as your last Claude Code
   message; after two hours without one, the account shows them "as of" that time. A window whose reset time has
   passed shows as empty.

The plan (Max, Ultra…) comes from the account info Claude Code keeps in `.claude.json`. Usage history (weekly % per
account, 35 days) is kept in `~/Library/Application Support/AgentsUsageWatch/history.jsonl` for trends and alerts.
The menu bar app writes a snapshot into an app-group container; the sandboxed widget only reads it. No analytics.

## Build

Needs Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig   # set your team ID and bundle ID prefix
./install.sh                                              # builds, installs to ~/Applications and starts it
```

The widget needs a signing team for its app group; a free Apple ID team is enough for a local build.
The app adds itself as a login item on first launch (turn it off in Settings › General).

`./install.sh --testing` builds a private testing variant with a second, token-based Claude source. It is meant for
the maintainer's own machine, is not distributed, and its code is compiled out of the normal build.

Watch it work: `log stream --predicate 'subsystem == "<your bundle prefix>.agentsusagewatch"'`.

Logic checks (parsers, the helper script end to end, alerts, maths), runnable without Xcode:

```sh
F="Shared/Model.swift App/Parse.swift App/Alerts.swift App/Accounts.swift App/StatusLine.swift Checks/ModelCheck/main.swift"
swiftc -o /tmp/chk $F && /tmp/chk
```

## Layout

| Path | What |
|---|---|
| `App/` | Menu bar app: status line source (`StatusLine`), accounts (`Accounts`), parsing (`Parse`), alert rules (`Alerts`), state (`Store`), UI |
| `App/Resources/statusline.sh` | The status line helper the app installs on Set Up |
| `Widget/` | WidgetKit extension: timeline, widget settings, refresh intent |
| `Shared/` | Snapshot model and views used by both |
| `Checks/` | Fixture-based checks for the pure logic |
| `Tools/make-icon.swift` | Draws the app icon |

## License

MIT
