#!/usr/bin/env bash
# test-bt-speaker.sh — run loft-bt-speaker against a mocked bluetoothctl.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/tests/lib/assert.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
MOCK_BIN="$WORK/bin"
mkdir -p "$MOCK_BIN"
export STATE="$WORK/state" CALLS="$WORK/calls" LOG="$WORK/log"
# STATE holds "unpaired", "off", "on" (connect works) or "connected".
mock bluetoothctl 'echo "$*" >> "$CALLS"
s="$(cat "$STATE")"
case "$1" in
  info) [[ "$s" == unpaired ]] && exit 1
        [[ "$s" == connected ]] && echo "	Connected: yes" || echo "	Connected: no" ;;
  show) echo "	Powered: yes" ;;
  --timeout) [[ "$s" == on ]] && echo connected > "$STATE" ;;
esac
exit 0'
mock logger 'echo "$*" >> "$LOG"'

run() { # state
  echo "$1" > "$STATE"
  : > "$CALLS"; : > "$LOG"
  PATH="$MOCK_BIN:/usr/bin:/bin" BT_SPEAKER_MAC=AA:BB:CC:DD:EE:FF \
    bash "${ROOT}/control-plane/loft-bt-speaker.sh"
}

run connected
assert_eq "$?" 0 "connected speaker exits 0"
assert_absent "$(cat "$CALLS")" "connect" "does not reconnect a connected speaker"
assert_eq "$(cat "$LOG")" "" "logs nothing when connected"

run on
assert_contains "$(cat "$CALLS")" "--timeout 15 connect AA:BB:CC:DD:EE:FF" "connects a reachable speaker"
assert_contains "$(cat "$LOG")" "connected AA:BB:CC:DD:EE:FF" "logs the new connection"

run off
assert_eq "$?" 0 "unreachable speaker exits 0"
assert_contains "$(cat "$CALLS")" "connect" "tries an unreachable speaker"
assert_eq "$(cat "$LOG")" "" "an unreachable speaker is quiet"

run unpaired
assert_absent "$(cat "$CALLS")" "connect" "does not connect an unpaired speaker"
assert_contains "$(cat "$LOG")" "is not paired" "logs the missing pairing"

PATH="$MOCK_BIN:/usr/bin:/bin" BT_SPEAKER_MAC="" bash "${ROOT}/control-plane/loft-bt-speaker.sh" 2>/dev/null
assert_fails "$?" "fails without BT_SPEAKER_MAC"

finish
