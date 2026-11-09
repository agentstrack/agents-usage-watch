# Privacy

The short version: the app reads files your coding agents already write on your Mac, shows what it finds, and
sends nothing anywhere. This page lists every file it touches so you can check.

## Network

The public build makes **no network requests for your usage**, and has no analytics, crash reporting or update
checks. The only thing that touches the internet is a link in Settings › About, which opens agentstrack.ai in your
browser when you click it. Notifications are local.

You can check this yourself. The only networking code is in [`App/Fetcher.swift`](../App/Fetcher.swift), and it
sits inside `#if TESTING`, so it isn't compiled into normal builds:

```sh
grep -rn "URLSession\|URLRequest" App Shared Widget
```

`./install.sh --testing` builds a private variant for the maintainer's own machine. It adds a second, token-based
Claude source that reads a login from the Keychain and calls an unofficial usage endpoint. It is not part of the
download or a normal build, and not meant for distribution.

## Credentials

The app does not log in to anything and does not use, copy or store tokens. The one credentials file it opens is
Codex's `~/.codex/auth.json`, to check that a token or API key is present and to read the account email from the
token's payload. The token itself is not kept or sent. The public build never reads the Keychain.

## Files the app reads

| Path | Why |
|---|---|
| `~/` (folder names only) | Finds `~/.claude-*` folders |
| `~/.claude.json`, `<folder>/.claude.json` | Claude Code account info: email, account id, plan tier |
| `~/.claude/settings.json`, `<folder>/settings.json` | The current `statusLine` command (read; rewritten by Set Up and Remove) |
| `~/.codex/auth.json` | Is a Codex login present, and its email |
| `~/.codex/sessions/**/rollout-*.jsonl` | Codex limits: the last 512 KB of up to 8 recent logs; only the rate-limit lines are used |
| `~/.gemini/antigravity-cli/` | Detects Antigravity; its `settings.json` is handled like Claude Code's |
| `~/.local/share/opencode/opencode.db` | opencode spend, read-only. The query sums token counts and cost for assistant messages; it doesn't read message text. |
| `~/Library/Sounds` | Lists your own notification sounds |
| `~/.agentsusagewatch/` | The limits the helper scripts saved |

The helper scripts receive the agent's full status JSON on stdin. They keep only the limits (`rate_limits` for
Claude Code; `quota` and the plan name for Antigravity) and pass the rest to your previous status line command
unchanged. They are plain shell scripts, using only macOS tools: [`statusline.sh`](../App/Resources/statusline.sh)
and [`statusline-agy.sh`](../App/Resources/statusline-agy.sh).

## Files the app writes

| Path | What |
|---|---|
| `~/.agentsusagewatch/statusline`, `statusline-agy` | Copies of the helper scripts, written when you click Set Up |
| `~/.agentsusagewatch/claude/<key>.json` | Saved Claude `rate_limits` (percentages and reset times), one file per config folder |
| `~/.agentsusagewatch/claude/<key>.next` | Your previous status line command, so the helper can run it |
| `~/.agentsusagewatch/antigravity/quota.json`, `agy.next` | The same for Antigravity |
| `settings.json` of a set-up agent | `statusLine` is pointed at the helper. The file is re-written as pretty-printed JSON, so its formatting and key order may change. |
| `settings.json.agentsusagewatch-backup` | A copy of `settings.json` made the first time you click Set Up |
| `~/Library/Application Support/AgentsUsageWatch/history.jsonl` | Usage history: time, account id (the config folder path), weekly percent and weekly reset time. Kept 35 days. |
| `~/Library/Application Support/AgentsUsageWatch/flavor` | Written by `install.sh` only: which build flavor is installed |
| `~/Library/Group Containers/<TEAM ID>.group.agentsusagewatch/usage.json` | The snapshot for the widgets: account names, plans, percentages, reset times, chart points. No emails. |
| App group preferences | Which account each small widget shows |
| `~/Library/Preferences/<bundle id>.plist` | Settings, the account list (names, folder paths, emails, plan), and the keys of alerts already sent |
| `~/Library/Sounds/AgentsUsageWatch <name>` | A copy of the system sound you picked for alerts |
| Login item | Registered with `SMAppService` so the app starts at login |

Nothing else is written. [Uninstall](installation.md#uninstall) removes all of it.

## Sandboxing

The menu bar app is **not sandboxed**: it has to read the agents' files in your home folder and edit their
`settings.json`. Its only entitlement is the app group. The widget extension **is sandboxed**; it can't read your
home folder, and only reads `usage.json` from the app group.
