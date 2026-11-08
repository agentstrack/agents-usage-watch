#!/bin/sh
# AgentsUsageWatch status line helper for the Antigravity CLI (agy).
# agy pipes its status JSON to this script. The script keeps only the "quota" part (your 5-hour and weekly
# limits) and the plan name for the AgentsUsageWatch app, then runs the status line command you had before,
# so your status line looks the same as it did. Only macOS tools are used: no network, nothing else is saved.
input=$(cat)
out="$HOME/.agentsusagewatch/antigravity"
/bin/mkdir -p "$out"
if q=$(printf '%s' "$input" | /usr/bin/plutil -extract quota json -o - - 2>/dev/null); then
  plan=$(printf '%s' "$input" | /usr/bin/plutil -extract plan_tier raw -o - - 2>/dev/null | /usr/bin/tr -d '"\\')
  printf '{"quota":%s,"plan":"%s"}' "$q" "$plan" > "$out/quota.tmp" && /bin/mv -f "$out/quota.tmp" "$out/quota.json"
fi
if [ -f "$out/agy.next" ]; then
  printf '%s' "$input" | /bin/sh -c "$(/bin/cat "$out/agy.next")"
fi
