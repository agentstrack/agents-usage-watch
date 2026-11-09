# Notifications

Settings › Notifications. All alerts are sent by the app itself, as ordinary macOS notifications. Nothing goes
through a server.

## What triggers an alert

Alerts are checked after every refresh, for accounts that are ticked **Menu bar** in Settings › Accounts and
whose data is current (not marked "Last used"). opencode never alerts: it has no limit.

| Alert | When | Default |
|---|---|---|
| **5-hour threshold** | The 5-hour window crosses your warn or alert level | 80% and 95% |
| **Weekly threshold** | The weekly window crosses your warn or alert level | 80% and 95% |
| **May run out before the weekly reset** | At this week's pace you'd reach 100% before the reset. Needs at least 15% of the week gone and the account still under 100%. | on |
| **Mid-week: on track to leave a lot unused** | At least half the week is gone and the projection is under 60% | on |
| **Burning much faster than usual** | The last hour added at least 2% of the week and at least 3 times your median active hour of the past 7 days. Needs 12 or more active hours of history first, so it stays quiet for the first few days. | on |

Threshold levels can be 50, 60, 70, 75, 80, 85, 90, 95 or 99%.

How often each one fires:

- Thresholds: once per window. If a window goes from 70% to 96% between two refreshes, you get one alert for the
  95% level, not two. The next window starts fresh.
- Run out and mid-week forecast: once per week per account.
- Burn rate: at most once per 3-hour period.

## Quiet hours

On by default, from 23:00 to 08:00 (change either hour). During quiet hours nothing is sent and nothing is marked
as sent, so anything still true when quiet hours end is sent then. Setting the same hour for both effectively
turns them off.

## Permission

The app asks for permission on first launch. The **macOS permission** line shows where you stand:

| Shown | Meaning |
|---|---|
| Allow Notifications... | macOS hasn't been asked yet. Click it. |
| Allowed | Alerts and banners work. |
| Banners off | Allowed, but only in Notification Center. **Change...** opens the right System Settings page. |
| Off | Not allowed. **Open System Settings...** takes you to System Settings › Notifications › Agents Usage Watch. |

If sounds are off for the app in System Settings, a note under the sound options says none will play.

An alert counts as sent only once macOS accepted it. If notifications were off when an alert came due, it is sent
after you allow them, as long as it's still true.

**Send Test Notification** posts a test and tells you what happened: sent, sent to Notification Center only
(banners off), or not sent because notifications are off.

## Sounds

Turn **Play a sound** off for silent notifications. Otherwise choose **System default** or one of:

- the Mac's alert sounds (from `/System/Library/Sounds`);
- your own sounds in `~/Library/Sounds`, as `.aiff`, `.aif`, `.wav` or `.caf` files.

The sound plays when you pick it. To use your own, put the file in `~/Library/Sounds` and reopen Settings.

macOS only plays notification sounds from `~/Library/Sounds` (or the app itself), so when you pick a system sound
the app copies it there as `AgentsUsageWatch <name>.aiff`. Only the current pick's copy is kept. Files starting
with `AgentsUsageWatch ` are hidden from the sound list.

## Focus modes

A Focus (Do Not Disturb, Work, Sleep and so on) silences notifications from apps it doesn't allow. If alerts never
arrive during a Focus, allow the app in it:

**System Settings › Focus › (your Focus) › Allowed Notifications** (or **Apps**), then add Agents Usage Watch.

The app marks urgent alerts **Time Sensitive**. Every alert except the mid-week forecast is urgent, and so is the
test notification. A Focus that allows Time Sensitive notifications would let those through without adding the app.
But macOS only honours that for apps signed with the Time Sensitive Notifications entitlement
(`com.apple.developer.usernotifications.time-sensitive`), and **current builds don't have it yet**. Until they do,
Time Sensitive is ignored and every alert is an ordinary notification, so the Focus has to allow the app by name.

The test button says as much: "In a Focus it only shows if that Focus allows Agents Usage Watch."
