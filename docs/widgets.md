# Widgets

Add them from the desktop or Notification Center: right-click › **Edit Widgets** › **Agents Usage Watch**. There
are two widgets, each in small, medium and large.

The widgets don't read anything from the agents themselves. The menu bar app writes a snapshot, and the widgets
draw it (see [Architecture](architecture.md)). The app has to be running for them to stay current.

## Usage

Named **Agents Usage Watch** in the gallery.

| Size | What it shows |
|---|---|
| Small | One account: a ring with the weekly percentage, and the 5-hour line (or the weekly reset countdown when the plan has no 5-hour window). An opencode account shows today's cost and tokens instead. |
| Medium | One row per account: the weekly bar, the 5-hour percentage next to the weekly one, and "Week resets in ... · +x%/day". |
| Large | Header with "Updated ..." and a refresh button, then up to 4 account cards (weekly bar, reset countdown, trend and projection, 5-hour line). |

### Switching accounts on the small widget

With more than one account, the account name in the small widget's header has a chevron. Click it to step to the
next account. The choice is remembered. It is stored once per widget type, so two small Usage widgets switch
together.

### Many accounts

The medium and large widgets try to show every account first:

- Medium: rows with captions, then rows without captions (the reset countdown moves next to the bar), then the
  first 3 accounts, then the first 2.
- Large: cards (when there are at most 4 accounts), then smaller cards, then list rows, then the first 6 or the
  first 4 rows.

When some accounts don't fit, a footnote reads **+N more · right-click › Edit Widget to choose**. Open Edit Widget
and pick the accounts you want, or use a larger size.

## Usage Progress

Shows how the weekly percentage grew over time, one line per account, in the same colours as the legend.

| Size | What it shows |
|---|---|
| Small | One account's week against an even-pace line (above the line means ahead of pace), the header switches account, and a trend line below. |
| Medium | All chosen accounts in one chart, with a legend showing each account's current weekly percentage. |
| Large | Same as medium, plus a trend line when only one account is shown. |

Accounts that only report spend (opencode) are left out: they have no weekly percentage. The history behind the
chart is kept by the app for 35 days; the widget gets the last 28 days.

## Edit Widget options

Right-click the widget › **Edit "..."**.

| Option | Usage | Usage Progress |
|---|---|---|
| Accounts | yes | yes |
| Background: Standard, Transparent, Tinted | yes | yes |
| Weekly pace marker | yes | no |
| Trend & projection | yes | no |
| Period: This week, Last 4 weeks | no | yes |

**Accounts:** leave it empty to show every account. If you pick some, only those appear, in the order set in
Settings › Accounts (drag to reorder). If a picked account was removed, the widget says "None of the chosen
accounts are in the data."

An account must also have its **Widgets** checkbox on in Settings › Accounts to be offered here. Accounts with it
off don't appear in the picker at all.

## Refreshing

- Clicking a widget asks the app to refresh. The large Usage widget also has a refresh
  button in its header.
- A status note such as "Set up in Settings" is a link: it opens the app's Settings.
- Countdowns tick every minute on their own. New values arrive when the app has new data.

macOS limits how often an app may reload widgets (roughly 40 to 70 times a day). So the app reloads them when a
shown value changes, at most once every 15 minutes, unless you click refresh. If the widget says
**App not running**, the app missed its planned refresh by more than 10 minutes: it isn't running, or the Mac was
asleep. Open the app.

More fixes are in [Troubleshooting](troubleshooting.md).
