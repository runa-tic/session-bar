#!/bin/bash
# Print the account-wide session list, as Claude Code's ListAgents tool returns it.
#
# Only a session connected to Remote Control is handed that list, and a headless
# `claude -p` is not one. So: start a short background session, let a PostToolUse
# hook save the tool result, then remove the session.
# Each run is one small Haiku turn against the subscription, and leaves that
# session's transcript under ~/.claude/projects/ (`claude rm` keeps it).
set -uo pipefail

CLAUDE="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
NAME="${ROSTER_NAME:-sessionbar-roster}"
# Must be a directory already trusted in Claude Code, or --bg refuses to start.
CWD="${ROSTER_CWD:-$HOME/Desktop}"
CACHE="$HOME/Library/Caches/SessionBar"
OUT="$CACHE/peers.json"
TIMEOUT="${ROSTER_TIMEOUT:-60}"

PROMPT="Call the ListAgents tool. If its output has no row marked Remote Control, call it again, up to 8 times in total. Then reply with the single word done."
# User settings are left out so the user's own hooks and plugins don't run for this
# helper; Remote Control is switched on here instead.
SETTINGS='{"remoteControlAtStartup":true,"hooks":{"PostToolUse":[{"matcher":"ListAgents","hooks":[{"type":"command","command":"cat > '"'$OUT.tmp'"' && mv -f '"'$OUT.tmp'"' '"'$OUT'"'"}]}]}}'

id=""
remove() {
    [ -n "$1" ] || return 0
    "$CLAUDE" stop "$1" </dev/null >/dev/null 2>&1
    "$CLAUDE" rm "$1" </dev/null >/dev/null 2>&1
}
trap 'remove "$id"' EXIT

mkdir -p "$CACHE"
rm -f "$OUT" "$OUT.tmp"

# A run that was killed can leave its helper behind; clear any before starting another.
for stale in $("$CLAUDE" agents --json --all </dev/null 2>/dev/null |
    /usr/bin/python3 -c 'import json,sys
for s in json.load(sys.stdin):
    if s.get("name") == sys.argv[1] and s.get("id"): print(s["id"])' "$NAME" 2>/dev/null); do
    remove "$stale"
done

started=$(cd "$CWD" && "$CLAUDE" --bg "$PROMPT" --name "$NAME" --model haiku \
    --tools ListAgents --allowedTools ListAgents \
    --setting-sources local --settings "$SETTINGS" </dev/null 2>&1)
id=$(printf '%s\n' "$started" | awk '$1 == "backgrounded" { print $3; exit }')
if [ -z "$id" ]; then
    printf 'could not start the helper session: %s\n' "$started" >&2
    exit 1
fi

# The first call can land before Remote Control has connected and list only this
# machine, so wait for a capture that includes Remote Control rows.
deadline=$((SECONDS + TIMEOUT))
while [ "$SECONDS" -lt "$deadline" ]; do
    if [ -f "$OUT" ] && grep -q "Remote Control" "$OUT"; then
        cat "$OUT"
        exit 0
    fi
    sleep 0.5
done

if [ -f "$OUT" ]; then
    echo "the helper session never saw Remote Control sessions" >&2
else
    echo "the helper session returned nothing within ${TIMEOUT}s" >&2
fi
exit 1
