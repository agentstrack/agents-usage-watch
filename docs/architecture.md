# Architecture

Two processes, one file between them:

```
 agent files on disk                     menu bar app (not sandboxed)                widget extension (sandboxed)
 ~/.codex/sessions          ─┐        ┌─────────────────────────────────┐
 opencode.db                 ├─ read ─▶  Providers / StatusLine readers   │
 ~/.agentsusagewatch/*.json ─┘        │      │  FetchResult              │
   ▲ written by helper scripts        │      ▼                           │
   │ (run by Claude Code / agy)       │   Store: rows, history, alerts   │
                                      │      │                           │
                                      │      ├─▶ notifications           │
                                      │      └─▶ usage.json ─────────────┼──▶ app group ──▶ Snapshot.load() ─▶ views
                                      └──────────────▲──────────────────┘                    │
                                                     └──── Darwin notification "refresh" ◀───┘ (refresh button)
```

The widget never reads the agents' files and never writes data. This is both a constraint (a sandboxed extension
can't see your home folder) and a decision: only one component decides what the numbers are.

## Source layout

| Path | What |
|---|---|
| [`App/App.swift`](../App/App.swift) | Entry point: `MenuBarExtra` (window style) plus the Settings scene, login item, URL handling, menu bar label |
| [`App/Store.swift`](../App/Store.swift) | `Store`: accounts, refresh loop, rows, history, widget snapshot, notifications and sounds |
| [`App/Accounts.swift`](../App/Accounts.swift) | `Account`, discovery and merge, and the readers: `Providers`, `Codex`, `Antigravity`, `OpenCode` |
| [`App/StatusLine.swift`](../App/StatusLine.swift) | Claude Code and Antigravity: read the helper's saved files, Set Up and Remove |
| [`App/Parse.swift`](../App/Parse.swift) | Pure parsers for each agent's format |
| [`App/Alerts.swift`](../App/Alerts.swift) | Pure alert rules and history maths |
| [`App/MenuView.swift`](../App/MenuView.swift), [`App/SettingsView.swift`](../App/SettingsView.swift) | The panel and Settings |
| [`App/Resources/`](../App/Resources) | The two helper scripts, copied into the app bundle |
| [`App/Fetcher.swift`](../App/Fetcher.swift) | Testing build only (compiled out otherwise), apart from a `Bundle.version` helper |
| [`Widget/UsageWidget.swift`](../Widget/UsageWidget.swift) | The two widgets, timeline providers, layouts per family |
| [`Widget/Config.swift`](../Widget/Config.swift) | Widget options (App Intents), account picker, refresh and account-switch intents |
| [`Shared/Model.swift`](../Shared/Model.swift) | `Row`, `Snapshot`, `Spend` and usage maths, used by both targets |
| [`Shared/Views.swift`](../Shared/Views.swift) | Bars, cards, charts, status notes, used by both targets |
| [`Checks/ModelCheck/main.swift`](../Checks/ModelCheck/main.swift) | Fixture-based checks for the pure logic |
| [`project.yml`](../project.yml) | XcodeGen definition of both targets |
| [`Config/`](../Config) | Shared build settings and the local team/prefix file |

The Xcode project, `Info.plist` files and entitlements are generated from `project.yml` by XcodeGen and are
git-ignored.

## The data model

Every reader produces a `FetchResult`:

- `.ok(windows, plan, at)`: 5-hour and weekly percentages and reset times, and when the agent last reported;
- `.spend(spend, at)`: usage without a limit (opencode);
- `.failed(status, ...)`: a `Row.Status` such as `notConnected` or `waiting`.

`Store.apply` turns that into a `Row` (the thing shown), keeping the last good values when a read fails. A row is
`idle` when its data is more than 2 hours old. Windows whose reset has passed read as 0% (`Row.applyingResets`).
Derived numbers (pace, projection, trend, today) are computed from the row and the history.

History is one JSON line per sample in `history.jsonl`, added when the weekly value changes or 10 minutes pass,
and pruned after 35 days. It feeds the progress chart, "today" and the burn-rate alert.

## The refresh loop

`Store.refresh()` runs one pass at a time:

1. Pick accounts that are shown in the menu or the widgets.
2. Read each: `Providers.read` for Codex, Antigravity and opencode, otherwise `StatusLine.read` (Claude Code).
   All of these are local file reads.
3. Apply results, append history, write the snapshot, then evaluate and post alerts.
4. Schedule the next pass.

The interval is set in Settings (30 seconds up to 15 minutes, default 5 minutes). A pass also runs at launch,
after a rescan, when you change a setting, 5 seconds after the Mac wakes (the timer is stopped on sleep), when you
press refresh in the panel, and when a widget asks for one. A widget asks in two ways: its refresh button posts a
Darwin notification (`agentsusagewatch.refresh`) because a sandboxed extension can't do the reading itself, and a
tap on the widget opens `agentsusagewatch://refresh`. The other URL, `agentsusagewatch://settings`, opens
Settings.

## The snapshot and the widget reload budget

After each pass the app writes `usage.json` to the app group: `Snapshot` holds `updated`, `nextUpdate`, the rows
of accounts that are enabled for widgets, and `series` (28 days of weekly percentages, one point per 2 hours, since
the widget can't read the history file). The app group id comes from the `AppGroup` key in each Info.plist, set
from `APP_GROUP_ID` in [`Config/Base.xcconfig`](../Config/Base.xcconfig).

macOS gives an app only a limited number of widget reloads a day (roughly 40 to 70). So:

- `Store.writeSnapshot` calls `reloadAllTimelines()` only when what the widget draws has changed (whole percents,
  reset minutes, names, plans, statuses, order), and at most every 15 minutes. User actions (refresh, rename,
  reorder) skip the limit.
- Between reloads, the Usage widget's timeline has 30 entries, one per minute, so countdowns keep moving. The
  progress widget has one entry; its chart only changes with new data. Both ask for a new timeline after 30
  minutes as a fallback.
- The widget decides the app is gone if `now` is more than 10 minutes past `nextUpdate` (`Snapshot.isStale`), and
  shows "App not running".

Per-widget settings (accounts, background, pace, trend, period) are App Intents parameters
([`Widget/Config.swift`](../Widget/Config.swift)). The small widgets' selected account is a counter in app-group
`UserDefaults`, one per widget kind. WidgetKit gives intents no instance id, hence one per kind.

## Alerts

[`Alerts.evaluate`](../App/Alerts.swift) is a pure function: rows, history, settings, the set of keys already
sent and the time go in; the alerts to post come out. Each alert has a key that includes the account and the
window's reset time, which is how "once per window" works. `Store.notify` posts them and records a key as sent
only after macOS accepted the request. Quiet hours return nothing without recording anything. Sounds and the
Time Sensitive flag live in `Notifications` in [`Store.swift`](../App/Store.swift); see
[Notifications](notifications.md).

## Why a status line helper

Claude Code and Antigravity don't publish their limits in a file. They do hand them to a configured status line
command. Reading the limits from there means no token use, no Keychain access, no network, and no dependence on an
unofficial endpoint. The cost is that the numbers only update while you use the agent, and that Set Up edits
`settings.json`, which is why the app backs it up first and why Remove restores the previous command.

## Adding an agent

Agents without a status line are small. Use `Codex` or `OpenCode` in [`App/Accounts.swift`](../App/Accounts.swift)
as a template.

1. **Write a reader**: an `enum` with `discover() -> [Account]` (return an `Account` with a new `provider` string,
   or nothing if the agent isn't installed) and `read(_ account:) -> FetchResult`. Read local files only.
2. **Register it** in the two functions in `Providers`: add it to `Providers.discover()` and add a `case` for
   your `provider` string in `Providers.read(_:)`.
3. **Parse in `Parse`** and keep the parser free of I/O so it can be checked from a fixture. Be tolerant: the
   formats belong to other tools and change.
4. **Add a fixture check** to [`Checks/ModelCheck/main.swift`](../Checks/ModelCheck/main.swift) with ids and
   personal data stripped.

Rows, widgets, alerts and Settings are generic, so nothing else needs to change. If the agent has no limit,
return `.spend` like opencode.

If the agent has a status line like Claude Code's, you also need a helper script in `App/Resources/`, entries for
it in `StatusLine.installHelper` and `StatusLine.settingsFile`, and `usesStatusLine` on `Account`. Antigravity
shows how.

Rules for contributions are in [CONTRIBUTING.md](../CONTRIBUTING.md): local files only, no network, never touch
credentials.

## The logic checks

The checks cover the parsers, the helper scripts end to end, alert rules and the maths. They need no Xcode:

```sh
swiftc -o /tmp/chk Shared/Model.swift App/Parse.swift App/Alerts.swift App/Accounts.swift \
  App/StatusLine.swift Checks/ModelCheck/main.swift && /tmp/chk
```

It prints `ok: all checks passed` or the line that failed. Add `-D TESTING` to also check the testing build's
token source. [CI](../.github/workflows/checks.yml) runs the same command on every push and pull request.

## Build flavors

`./install.sh` builds the public flavor. `./install.sh --testing` defines the `TESTING` compilation condition,
which compiles in the maintainer's private token-based Claude source. The installed flavor is recorded in
`~/Library/Application Support/AgentsUsageWatch/flavor`, and a plain `./install.sh` rebuilds that same flavor so
it never silently swaps one for the other.
