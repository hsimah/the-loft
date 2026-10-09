#!/usr/bin/env bash
# test-dashboard-power.sh — drive loft-dashboard-power's functions against a
# mocked X display (xset, xprintidle) and recorded Snapserver messages.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/tests/lib/assert.sh"
require jq

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
MOCK_BIN="$WORK/bin"
mkdir -p "$MOCK_BIN"
export MON="$WORK/monitor" IDLE="$WORK/idle" CALLS="$WORK/calls"
# The monitor state lives in a file; force on/off changes it like DPMS would.
mock xset 'case "$1" in
  q) [[ -s "$MON" ]] && printf "DPMS (Display Power Management Signaling):\n  DPMS is Enabled\n  Monitor is %s\n" "$(cat "$MON")" ;;
  dpms) echo "force $3" >> "$CALLS"; [[ "$3" == on ]] && echo On > "$MON" || echo Off > "$MON" ;;
esac'
mock xprintidle '[[ -s "$IDLE" ]] && cat "$IDLE" || exit 1'
PATH="$MOCK_BIN:$PATH"
# Never reach the real display.
for c in xset xprintidle; do
  [[ "$(command -v "$c")" == "$MOCK_BIN/$c" ]] || { echo "FAIL   $c is not mocked" >&2; exit 1; }
done

LOFT_POWER_GROUPS=" syncgroup28jexljs , syncgroupzewbtz9n,"
source "${ROOT}/control-plane/loft-dashboard-power.sh"

display() { # monitor-state idle-ms
  echo "$1" > "$MON"
  if [[ -n "$2" ]]; then echo "$2" > "$IDLE"; else : > "$IDLE"; fi
  : > "$CALLS"
}
reset_streams() { local g; for g in "${!STATES[@]}"; do STATES[$g]=idle; done; }
calls() { cat "$CALLS"; }
props() { # stream-id playbackStatus
  jq -cn --arg id "$1" --arg s "$2" \
    '{jsonrpc: "2.0", method: "Stream.OnProperties", params: {id: $id, properties: {playbackStatus: $s}}}'
}

# ── configuration ────────────────────────────────────────────────────────────
assert_eq "$(printf '%s\n' "${!STATES[@]}" | sort | paste -sd, -)" "syncgroup28jexljs,syncgroupzewbtz9n" \
  "groups are parsed with whitespace and empty entries dropped"

# ── blanking on idle ─────────────────────────────────────────────────────────
display On 600000
out="$(idle_check)"
assert_eq "$(calls)" "force off" "blanks after the idle threshold"
assert_contains "$out" "screen off" "logs the blank"

display On 599999
idle_check > /dev/null
assert_eq "$(calls)" "" "does not blank before the threshold"

display Off 900000
idle_check > /dev/null
assert_eq "$(calls)" "" "does not re-blank a blank screen"

# The #119 regression: a touch wakes the panel behind the daemon's back, and
# the next idle period must still blank it.
display On 600000
idle_check > /dev/null
echo On > "$MON"
idle_check > /dev/null
assert_eq "$(calls | paste -sd, -)" "force off,force off" "blanks again after a touch wake"

display On 900000
STATES[syncgroupzewbtz9n]=playing
idle_check > /dev/null
assert_eq "$(calls)" "" "never blanks while a watched group plays"
reset_streams

display On ""
out="$(idle_check)"
assert_eq "$(calls)" "" "unknown idle time never blanks"
assert_contains "$out" "xprintidle failed" "logs the xprintidle failure"

display On 900000
: > "$MON"
idle_check > /dev/null
assert_eq "$(calls)" "force off" "unknown monitor state still blanks"

# ── waking on playback ───────────────────────────────────────────────────────
display Off 0
out="$(handle_message "$(props "Music Assistant - syncgroup28jexljs" playing)"; declare -p STATES)"
assert_eq "$(calls)" "force on" "Upstairs playback wakes the screen"
assert_contains "$out" "syncgroup28jexljs -> playing" "logs the state change"
assert_contains "$out" '[syncgroup28jexljs]="playing"' "records the playing state"

display On 0
handle_message "$(props "Music Assistant - syncgroupzewbtz9n" playing)" > /dev/null
assert_eq "$(calls)" "" "playback leaves an awake screen alone"
reset_streams

display Off 0
handle_message "$(props "Music Assistant - syncgroupbkmvcshl" playing)" > /dev/null
handle_message "$(props "Spotify - syncgroup28jexljs" playing)" > /dev/null
handle_message 'not json' > /dev/null
handle_message '{"jsonrpc":"2.0","method":"Client.OnVolumeChanged","params":{}}' > /dev/null
assert_eq "$(calls)" "" "ignores unwatched streams, other sources, junk and other events"

# ── connection session ───────────────────────────────────────────────────────
# A recorded connection: the GetStatus reply shows All playing, then it stops.
status_reply="$(jq -cn '{id: 1, jsonrpc: "2.0", result: {server: {streams: [
  {id: "Music Assistant - syncgroupzewbtz9n", status: "playing", properties: {playbackStatus: "playing"}},
  {id: "Music Assistant - syncgroup28jexljs", status: "idle", properties: {}},
  {id: "Music Assistant - syncgroupbkmvcshl", status: "playing", properties: {playbackStatus: "playing"}}]}}}')"
printf '%s\n%s\n' "$status_reply" "$(props "Music Assistant - syncgroupzewbtz9n" stopped)" > "$WORK/inbound"
display Off 0
exec 5< "$WORK/inbound" 6> "$WORK/outbound"
out="$(session 5 6; declare -p STATES)"
exec 5<&- 6>&-
assert_eq "$(jq -r .method "$WORK/outbound")" "Server.GetStatus" "asks for every stream's state on connect"
assert_eq "$(calls)" "force on" "GetStatus seeds state and wakes for a group already playing"
assert_contains "$out" '[syncgroupzewbtz9n]="stopped"' "later notifications update the state"
assert_contains "$out" '[syncgroup28jexljs]="idle"' "falls back to stream status without playbackStatus"
assert_absent "$out" "syncgroupbkmvcshl" "unwatched streams are not tracked"

finish
