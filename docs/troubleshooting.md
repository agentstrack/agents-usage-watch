# Troubleshooting

## macOS won't open the app

The prebuilt app is not notarized, so Gatekeeper blocks the first launch. Right-click the app › **Open**, or use
**System Settings › Privacy & Security › Open Anyway**, or run
`xattr -dr com.apple.quarantine "/Applications/Agents Usage Watch.app"`. Details in
[Installation](installation.md#first-launch-and-gatekeeper).

## Nothing happens when I click the menu bar item, or the panel is invisible

Menu bar managers such as Ice or Bartender hide items by parking them far off-screen. The panel opens under the
item's real position, so it can open where you can't see it.

The app handles this: if the panel's window isn't on any screen, it moves it to the top of the screen under your
pointer. If it still misbehaves, move Agents Usage Watch to the visible section of your menu bar manager.

## The menu bar item isn't there

The app has no Dock icon. If the gauge is missing, the app may not be running (open it again) or your menu bar
manager has hidden it. You can also set **Menu bar shows** to "Icon only" in Settings › General if the percentage
makes the item too wide for a crowded bar.

## A row says "Set up in Settings" or "Waiting for first message"

- **Set up in Settings:** Claude Code and Antigravity need **Set Up** in Settings › Accounts. See
  [Agents](agents.md).
- **Waiting for first message:** Set Up is done, but the agent hasn't sent a message since. Use the agent once.
  For Codex it means no rate-limit event exists in `~/.codex/sessions` yet.
- **Not logged in** (Codex): `~/.codex/auth.json` has no login. Log in to Codex.
- **Format changed:** the agent's data no longer matches what the app expects. The last good values stay. Please
  open an issue with your agent's version.

## Values look old, or a row says "Last used"

Limits are only as fresh as the agent's last message. After 2 hours without one, the row keeps its last values
and says "Last used" with the time. Use the agent and they update. See
[Freshness](agents.md#freshness-and-last-used).

## Codex shows 0% right after a reset

When a window's reset time passes, the app shows that window as 0% immediately. Codex only writes new numbers
during a session, so the real figure appears after your next Codex session. Same for the other agents with their
next message.

## No notifications

1. Open Settings › Notifications and look at **macOS permission**. If it says Off or Banners off, follow the link
   to System Settings.
2. Click **Send Test Notification**. It tells you if it was sent.
3. If the test says it was sent but you saw nothing, check for a **Focus** (Do Not Disturb and so on). Allow
   Agents Usage Watch in that Focus under System Settings › Focus › Allowed Notifications. Time Sensitive
   delivery needs an entitlement that current builds don't have yet, so the app must be allowed by name. See
   [Notifications](notifications.md#focus-modes).
4. Check that you aren't inside quiet hours (23:00 to 08:00 by default). Held alerts are sent afterwards.
5. Alerts are only raised for accounts ticked "Menu bar", with current data. A "Last used" account doesn't alert.

## No sound

Check **Play a sound** in Settings › Notifications, and that sounds are on for the app in System Settings ›
Notifications. A note in Settings appears when macOS has them off.

## A widget shows fewer accounts than the menu bar

- Open the widget's options (right-click › **Edit Widget**) and check **Accounts**. If you chose some accounts,
  only those are shown; empty means all.
- Check the **Widgets** checkbox for the account in Settings › Accounts. Accounts with it off aren't offered
  to widgets.
- The medium and large widgets show **+N more** when the rest doesn't fit. Pick fewer accounts, or use a larger
  size.
- The small widget shows one account at a time. Click its header to step to the next.

## The widget says "App not running"

The widget only draws what the menu bar app wrote. This warning appears when the app is more than 10 minutes late
with its planned refresh: it's not running, or the Mac was asleep. Open the app. It refreshes a few seconds after
the Mac wakes.

## The widget says "No usage data yet"

The app has never written data. Open the menu bar app and wait for the first refresh. If you built your own copy,
check that app and widget were signed with the same team: they share data through an app group.

## The widget isn't in the gallery

Open the app once; that registers the widget with macOS. If it still isn't listed, quit the app and open it
again, or log out and in.

## Widgets update slowly

macOS limits how often an app may reload widgets, so the app only reloads them when a shown value changes, and at
most once every 15 minutes. Clicking a widget forces a refresh.

## My Claude Code status line looks different

Set Up keeps your previous status line command and runs it with the same input. If it looks wrong, click
**Remove** in Settings › Accounts, which puts the old command back, and open an issue. A copy of your original
`settings.json` is next to it as `settings.json.agentsusagewatch-backup`.

## Looking at the logs

```sh
log stream --predicate 'subsystem == "<bundle id>"'
```

The bundle id is your prefix plus `.agentsusagewatch`. For an installed copy:

```sh
defaults read "/Applications/Agents Usage Watch.app/Contents/Info" CFBundleIdentifier
```

The app never logs tokens. Please don't paste `auth.json` or full session logs into an issue.
