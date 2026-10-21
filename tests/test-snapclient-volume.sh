#!/usr/bin/env bash
# test-snapclient-volume.sh — drive loft-snapclient-volume's .env parsing and
# Snapserver exchange against recorded replies.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/tests/lib/assert.sh"
require jq

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SNAPSERVER_HOST=192.0.2.1 HOST_ID=woodstock SNAPCLIENT_VOLUME=075
source "${ROOT}/services/howlr/snapclient-volume.sh"
REPLY_SECS=1

# replies... -> set_volume's status; the request lands in $WORK/outbound
exchange() {
  printf '%s\n' "$@" > "$WORK/inbound"
  exec 5< "$WORK/inbound" 6> "$WORK/outbound"
  set_volume 5 6
  local status=$?
  exec 5<&- 6>&-
  return "$status"
}

# ── .env ─────────────────────────────────────────────────────────────────────
cat > "$WORK/env" <<'EOF'
COMPOSE_PROFILES=client                            # "server" or "client"
SNAPSERVER_HOST=192.168.86.28                      # Snapserver IP address
# HOST_ID=commented-out
HOST_ID="sun room"
HOST_ID=woodstock
SNAPCLIENT_VOLUME=60# no space, so part of the value
EOF
assert_eq "$(env_value SNAPSERVER_HOST "$WORK/env")" "192.168.86.28" "strips an inline comment"
assert_eq "$(env_value HOST_ID "$WORK/env")" "woodstock" "last assignment wins, comments ignored"
printf 'HOST_ID="sun room"  # quoted\n' > "$WORK/quoted"
assert_eq "$(env_value HOST_ID "$WORK/quoted")" "sun room" "unquotes, keeping spaces"
env_value SOUND_DEVICE "$WORK/env" > /dev/null
assert_fails $? "reports a missing key"

out="$(load_env "$WORK/env"; printf '%s|%s|%s' "$SNAP_HOST" "$CLIENT_ID" "$VOLUME")"
assert_eq "$out" "192.168.86.28|woodstock|60# no space, so part of the value" "loads the client settings"
out="$(load_env "$WORK/env"; valid_config)"
assert_fails $? "rejects a volume with a glued-on comment"
grep -v SNAPCLIENT_VOLUME "$WORK/env" > "$WORK/novol"
out="$(load_env "$WORK/novol"; printf '%s' "$VOLUME")"
assert_eq "$out" "75" "defaults the volume to 75"
out="$(load_env "$WORK/missing")"
assert_fails $? "fails on a missing .env"
out="$(load_env "${ROOT}/services/howlr/.env.example"; printf '%s|%s' "$CLIENT_ID" "$VOLUME")"
assert_eq "$out" "change-me|75" "reads .env.example"

# ── configuration ────────────────────────────────────────────────────────────
valid_config > /dev/null
assert_eq "$?" 0 "accepts a zero-padded percentage"
for v in 101 -1 75% "" loud; do
  out="$(VOLUME="$v"; valid_config)"
  assert_fails $? "rejects SNAPCLIENT_VOLUME='${v}'"
done
assert_contains "$out" "must be 0-100" "explains the rejection"
out="$(CLIENT_ID=""; valid_config)"
assert_fails $? "rejects an empty HOST_ID"

# ── request ──────────────────────────────────────────────────────────────────
req="$(volume_request woodstock 075)"
assert_eq "$(jq -r .method <<< "$req")" "Client.SetVolume" "sends Client.SetVolume"
assert_eq "$(jq -c .params <<< "$req")" '{"id":"woodstock","volume":{"muted":false,"percent":75}}' \
  "targets the host id, unmuted, as a number"

# ── replies ──────────────────────────────────────────────────────────────────
notify='{"jsonrpc":"2.0","method":"Stream.OnProperties","params":{"id":"Music Assistant - syncgroup28jexljs","properties":{}}}'
exchange "$notify" '{"id":1,"jsonrpc":"2.0","result":{"volume":{"muted":false,"percent":75}}}' > /dev/null
assert_eq "$?" 0 "succeeds on the result, skipping notifications"
assert_eq "$(jq -c .params.volume "$WORK/outbound")" '{"muted":false,"percent":75}' "writes the request"

out="$(exchange '{"error":{"code":-32603,"message":"Client not found"},"id":1,"jsonrpc":"2.0"}')"
assert_fails $? "fails while the server has never seen the client"
assert_contains "$out" "Client not found" "logs the server's error"

out="$(exchange "$notify")"
assert_fails $? "fails when no reply arrives"
assert_contains "$out" "no reply" "logs the missing reply"

finish
