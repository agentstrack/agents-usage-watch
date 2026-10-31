#!/bin/sh
# AgentsUsageWatch status line helper.
# Claude Code pipes its status JSON to this script after each message. The script keeps only the
# "rate_limits" part (your 5-hour and weekly percentages) for the AgentsUsageWatch app, then runs the
# status line command you had before, so your status line looks the same as it did.
# Only macOS tools are used: no jq, no network, nothing else is saved.
input=$(cat)
dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
dir="${dir%/}"
key=$(printf '%s' "$dir" | /usr/bin/shasum -a 256 | /usr/bin/cut -c1-16)
out="$HOME/.agentsusagewatch/claude"
/bin/mkdir -p "$out"
if rl=$(printf '%s' "$input" | /usr/bin/plutil -extract rate_limits json -o - - 2>/dev/null); then
  printf '%s' "$rl" > "$out/$key.tmp" && /bin/mv -f "$out/$key.tmp" "$out/$key.json"
fi
if [ -f "$out/$key.next" ]; then
  printf '%s' "$input" | /bin/sh -c "$(/bin/cat "$out/$key.next")"
fi
