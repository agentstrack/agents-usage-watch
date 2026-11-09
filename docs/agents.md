# Agents

Agents Usage Watch does not ask any service for your usage. Each agent either writes its limits to a local file
already (Codex, opencode), or hands them to a status line command (Claude Code, Antigravity), which the app's
helper saves. So values are only as fresh as the agent's last message.

| Agent | Setup | Source |
|---|---|---|
| [Claude Code](#claude-code) | Set Up per account | status line JSON, saved by a helper |
| [OpenAI Codex CLI](#openai-codex-cli) | none | `~/.codex/sessions` logs |
| [Antigravity CLI](#antigravity-cli-agy) | Set Up | status line JSON, saved by a helper |
| [opencode](#opencode) | none | `~/.local/share/opencode/opencode.db` |

## How accounts are found

On launch, and when you click **Rescan** in Settings › Accounts, the app looks for:

- Claude Code logins in `~/.claude` and every `~/.claude-*` folder that holds a login (the account info file has
  an `oauthAccount`). Use **Add Folder…** for a `CLAUDE_CONFIG_DIR` folder with another name.
- Codex, if `~/.codex/auth.json` holds a login.
- Antigravity, if `~/.gemini/antigravity-cli` exists.
- opencode, if `~/.local/share/opencode/opencode.db` exists.

Accounts keep your names, order and hide flags across rescans. Discovered accounts whose folder disappears are
dropped; accounts you added with Add Folder stay until you remove them (the minus button).

In Settings › Accounts each account has two checkboxes: **Menu bar** (panel, menu bar value and notifications)
and **Widgets** (offered to the widgets). Each widget also has its own account list, see [Widgets](widgets.md).

## Claude Code

**Shows:** the 5-hour and weekly windows with percent used and reset times, and the plan (Pro, Max, Ultra).
Some plans have no 5-hour window (Ultra, at the time of writing); those accounts show the weekly bar only.

**Naming:** the default `~/.claude` login is called DEFAULT. Other folders take the last dash-separated part of
the folder name in capitals: `~/.claude-account-work` becomes WORK. Rename in Settings. If `~/.claude` is the
same login as one of the named folders, it is hidden on first discovery.

**Plan:** read from `organizationRateLimitTier` in the account info file. Claude Code still stores the old tier
names; `max_5x` is shown as Max and `max_20x` as Ultra.

**Where the limits come from:** Claude Code pipes a JSON status to its `statusLine` command after each message.
It includes `rate_limits` with `five_hour` and `seven_day` objects (`used_percentage`, `resets_at`). The app's
helper script, [`App/Resources/statusline.sh`](../App/Resources/statusline.sh), keeps only that part.

**Setup:** Settings › Accounts › **Set Up**.

1. The helper is copied to `~/.agentsusagewatch/statusline` (a path without spaces, so it can go into
   `settings.json` unquoted).
2. The account's `settings.json` is backed up once to `settings.json.agentsusagewatch-backup`.
3. Your existing `statusLine.command`, if any, is remembered in `~/.agentsusagewatch/claude/<key>.next`, and
   `statusLine.command` is set to the helper.
4. After each message the helper saves `rate_limits` to `~/.agentsusagewatch/claude/<key>.json`, then runs your
   previous command with the same input, so your status line looks the same.

`<key>` is the first 16 hex characters of the SHA-256 of the config folder path. The helper takes the folder from
`CLAUDE_CONFIG_DIR`, or `~/.claude` when it isn't set, so each folder keeps its own file.

If several config folders share one `settings.json` through a symlink, the app edits the real file (not a copy)
and remembers each account's previous command separately.

**Remove** restores your previous command, or deletes the `statusLine` entry if you had none. The backup file is
left in place.

The helper only uses macOS tools (`plutil`, `shasum`, `cut`, `mkdir`, `mv`). It makes no network requests.

**Before it works:** until Set Up is done the row says "Set up in Settings". After Set Up it says "Waiting for
first message" until Claude Code has sent one.

## OpenAI Codex CLI

**Shows:** the 5-hour and weekly windows where Codex reports them, and the plan Codex reports (for example
`plus`). The account email is shown in Settings.

**Where it comes from:** Codex writes token-count events with `rate_limits` into its session logs. The app opens
the 8 most recently modified `rollout-*.jsonl` files under `~/.codex/sessions`, reads the last 512 KB of each, and
takes the newest rate-limit line. Which of Codex's two windows is "primary" depends on the plan, so the app goes
by window length: 10 hours or less is the 5-hour window, anything longer is weekly.

**Setup:** none. It shows up if `~/.codex/auth.json` holds a login (a ChatGPT login or an API key).

**Login check:** the app opens `auth.json` only to see that a token or key is there and to read the email from the
token's payload. It does not use or store the token. If the login is gone, the row says "Not logged in".

**Before it works:** until Codex has written a rate-limit event the row says "Waiting for first message".

## Antigravity CLI (`agy`)

**Shows:** two accounts that share one login:

- **ANTIGRAVITY**: Gemini models, 5-hour and weekly.
- **ANTIGRAVITY 3P**: third-party models (Claude, GPT-OSS), with their own 5-hour and weekly limits. It is
  hidden by default; switch on its Menu bar and Widgets checkboxes to see it.

**Where it comes from:** like Claude Code, `agy` pipes a status JSON to a configured `statusLine` command. Its
`quota` object has `gemini-5h`, `gemini-weekly`, `3p-5h` and `3p-weekly` entries with a `remaining_fraction` and a
`reset_time`; the app shows used = (1 - remaining). The helper
[`App/Resources/statusline-agy.sh`](../App/Resources/statusline-agy.sh) saves the quota and the plan name to
`~/.agentsusagewatch/antigravity/quota.json`. The plan is shortened, so "Google AI Pro" shows as Pro.

**Setup:** Settings › Accounts › **Set Up**, the same procedure as Claude Code. The settings file is
`~/.gemini/antigravity-cli/settings.json`, the backup is `settings.json.agentsusagewatch-backup`, and your
previous command is kept in `~/.agentsusagewatch/antigravity/agy.next`. Both Antigravity rows share the one
setting, so Set Up on either connects both.

## opencode

**Shows:** spend, not a limit. There is no plan window, so the panel and widgets show cost and tokens instead of
bars: today, and the last 7 days.

**Where it comes from:** `~/.local/share/opencode/opencode.db`, opened read-only. The app sums assistant
messages:

- *Today* is since local midnight; *7 days* is the last 7 x 24 hours.
- *Tokens* are input + output + reasoning. Cache reads are left out, since they would swamp the count.
- *Cost* is the cost opencode recorded for each message.

**Setup:** none.

opencode accounts have no weekly percentage, so they don't appear in the progress chart or the Usage Progress
widget and never trigger notifications.

## Freshness and "Last used"

- A row is shown as current while its data is less than **2 hours** old. For Claude Code and Antigravity that is
  the time the helper last saved a value; for Codex the timestamp of the log event; for opencode the newest
  message.
- Older than that, the row keeps its last values and says **Last used** with the time (today's time, or the
  date). This is normal when you haven't used the agent.
- An opencode account with no messages in the last 7 days says "Not used yet".
- If the helper saved something the app can't read, the row says "Format changed" and keeps the last good values.
  The agents' formats belong to them and can change without notice.
- Rows with a problem show the status text in orange. The full list: Set up in Settings, Waiting for first
  message, Not logged in, Format changed, Couldn't update.

## Resets

Reset times come from the agent. Once a window's reset time has passed, the app shows that window as 0% straight
away, even if the agent hasn't reported since. The value is corrected at the next message. For Codex this means
you may see 0% after a reset while Codex still has older numbers in its logs; the real figure appears after your
next Codex session.

The pace marker on the weekly bar shows how much of the week has passed. The trend is the weekly percentage added
per day so far this week, and the projection is where the week ends if the rest goes at that rate (not shown in
the first few hours of a week).
