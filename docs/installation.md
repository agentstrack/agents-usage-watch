# Installation

Agents Usage Watch needs macOS 14 Sonoma or later. There are two ways to get it: a prebuilt download, or building
it yourself.

## Download

1. Download [Agents-Usage-Watch.zip](https://github.com/agentstrack/agents-usage-watch/releases/latest/download/Agents-Usage-Watch.zip)
   and unzip it (double-click in Finder).
2. Move **Agents Usage Watch.app** to your Applications folder. Do this before the first launch: the app adds
   itself as a login item from wherever it runs.
3. Open it for the first time using one of the options below.

### First launch and Gatekeeper

The app is signed with an Apple Development certificate but is **not notarized** yet (there is no Developer ID
certificate behind it). macOS therefore blocks the first launch. Pick one:

- **Right-click › Open.** In Finder, right-click the app, choose **Open**, then click **Open** in the dialog.
- **Open Anyway.** Try to open the app normally, then go to **System Settings › Privacy & Security**, scroll to
  the Security section and click **Open Anyway** next to the message about Agents Usage Watch.
- **Remove the quarantine flag.** In Terminal:

  ```sh
  xattr -dr com.apple.quarantine "/Applications/Agents Usage Watch.app"
  ```

You need to do this once per downloaded copy. If you'd rather not run an unnotarized binary, build it from
source (next section) and read the code first.

### After launching

A gauge icon appears in the menu bar. There is no Dock icon. The first time, the app:

- asks for notification permission;
- registers itself as a login item (see below);
- registers the widgets with macOS, so they show up under **Edit Widgets**.

Then continue with [Agents](agents.md) to set up Claude Code and Antigravity.

## Build from source

You need Xcode 15 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/agentstrack/agents-usage-watch.git
cd agents-usage-watch
cp Config/Local.xcconfig.example Config/Local.xcconfig   # set your team ID and a bundle ID prefix
./install.sh                                              # builds, installs to ~/Applications and starts it
```

[`install.sh`](../install.sh) runs XcodeGen to generate the Xcode project from [`project.yml`](../project.yml),
builds the Release configuration into `./build`, stops a running copy, copies the app to
`~/Applications/Agents Usage Watch.app` and opens it. Run it again to update.

### Signing team

The widget and the app share data through an app group, which needs a signing team. A free Apple ID team is
enough for local builds.

`Config/Local.xcconfig` is git-ignored and holds two values (see
[`Local.xcconfig.example`](../Config/Local.xcconfig.example)):

| Setting | What it is |
|---|---|
| `DEVELOPMENT_TEAM` | Your Apple team ID. Find it in Xcode › Settings › Accounts. |
| `BUNDLE_ID_PREFIX` | A reverse-DNS prefix that is unique to your team, for example `com.yourname`. The app becomes `<prefix>.agentsusagewatch` and the widget `<prefix>.agentsusagewatch.widget`. |

The app group id is derived from your team (`<TEAMID>.group.agentsusagewatch`) in
[`Config/Base.xcconfig`](../Config/Base.xcconfig), so a fork builds without further changes.

## Start at login

On first launch the app registers itself as a login item. To change it, use **Settings › General › Open at
login**, or **System Settings › General › Login Items**.

## Adding the widgets

Right-click the desktop (or open Notification Center) › **Edit Widgets** › **Agents Usage Watch**. See
[Widgets](widgets.md).

## Updating

- Prebuilt: quit the app from its menu, replace the app in Applications with the new one, open it.
- From source: `git pull && ./install.sh`.

Your accounts, settings and history are kept.

## Uninstall

1. **Restore the status lines first.** Open **Settings › Accounts** and click **Remove** next to every Claude
   Code and Antigravity account that shows it. This puts your previous `statusLine` command back in each
   `settings.json`. If you skip this step, the agent's `settings.json` keeps pointing at a helper script that
   no longer exists.
2. Turn off **Open at login** in Settings › General, then choose **Quit** in the menu bar panel.
3. Delete the app (`/Applications` or `~/Applications`).
4. Delete the data the app created:
   - `~/.agentsusagewatch` (the helper scripts and the limits they saved)
   - `~/Library/Application Support/AgentsUsageWatch` (usage history)

Optional leftovers:

- `settings.json.agentsusagewatch-backup`, next to each `settings.json` you used Set Up on.
- `~/Library/Sounds/AgentsUsageWatch *`: copies of the system sound you picked for alerts.
- `~/Library/Preferences/<your bundle id>.plist`: the app's settings. The prebuilt app's bundle id is in
  `Agents Usage Watch.app/Contents/Info.plist`.

See [Privacy](privacy.md) for the complete list of what the app writes.
