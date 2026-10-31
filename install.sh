#!/bin/bash
# Builds + installs the menu bar app to ~/Applications and starts it (it registers itself to open at login).
#   ./install.sh            public build: Claude limits from Claude Code's status line
#   ./install.sh --testing  private testing build: also reads Claude Code logins from the Keychain
set -euo pipefail
cd "$(dirname "$0")"
FLAGS=()
case "${1:-}" in
  --testing) FLAGS=(SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) TESTING') ;;
  "") ;;
  *) echo "usage: $0 [--testing]" >&2; exit 2 ;;
esac
xcodegen -q
xcodebuild -project AgentsUsageWatch.xcodeproj -scheme AgentsUsageWatch -configuration Release \
  -derivedDataPath build -allowProvisioningUpdates -quiet build ${FLAGS[@]+"${FLAGS[@]}"}

APP=AgentsUsageWatch
pkill -x "$APP" 2>/dev/null || true

# Replace the pre-0.2.0 app (ClaudeUsage). Its accounts, alert settings and history carry over once.
if [ -d ~/Applications/ClaudeUsage.app ]; then
  OLD=$(defaults read ~/Applications/ClaudeUsage.app/Contents/Info CFBundleIdentifier 2>/dev/null || true)
  NEW=$(defaults read "$PWD/build/Build/Products/Release/$APP.app/Contents/Info" CFBundleIdentifier)
  pkill -x ClaudeUsage 2>/dev/null || true
  if [ -n "$OLD" ] && ! defaults read "$NEW" >/dev/null 2>&1; then
    defaults export "$OLD" - | defaults import "$NEW" -
    defaults delete "$NEW" didSetupLoginItem 2>/dev/null || true   # register the new app at login
  fi
  SUP=~/Library/Application\ Support
  [ -d "$SUP/ClaudeUsage" ] && [ ! -d "$SUP/$APP" ] && mv "$SUP/ClaudeUsage" "$SUP/$APP"
  rm -rf ~/Applications/ClaudeUsage.app
fi
for P in ~/Library/LaunchAgents/*.claude-usage.plist; do   # 0.0.x refresh job
  [ -f "$P" ] && { launchctl bootout gui/$UID "$P" 2>/dev/null || true; rm -f "$P"; }
done

mkdir -p ~/Applications && rm -rf ~/Applications/$APP.app
cp -R build/Build/Products/Release/$APP.app ~/Applications/
open ~/Applications/$APP.app   # also registers the widget with the system
