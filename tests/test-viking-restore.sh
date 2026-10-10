#!/usr/bin/env bash
# test-viking-restore.sh — exercise hosts/viking/restore's ordering and gates
# against mocked host commands, with every host path moved into a temp dir.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/tests/lib/assert.sh"
require jq

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SCRIPT="$WORK/hosts/viking/restore"
mkdir -p "$WORK/hosts/viking" "$WORK/control-plane" "$WORK/etc/loft"
sed -e 's/\[\[ \$EUID -eq 0 \]\]/[[ 0 -eq 0 ]]/' \
    -e "s#/etc/loft/dmz-ready#${WORK}/etc/loft/dmz-ready#g" \
    -e "s#/var/backups/loft#${WORK}/var/backups/loft#g" \
    -e "s#/var/lib/loft/deploy#${WORK}/var/lib/loft/deploy#g" \
    "${ROOT}/hosts/viking/restore" > "$SCRIPT"
touch "$WORK/etc/loft/dmz-ready"
echo 'printf "%s|%s\n" "$LOFT_FORCE_DEPLOY" "$*" >> "$FIXTURE/deploy-calls"' \
  > "$WORK/control-plane/pawst-deploy.sh"

MOCK_BIN="$WORK/bin"
mkdir -p "$MOCK_BIN"
mock hostname  'echo viking'
mock id        'echo 1003'
mock nft       'exit 0'
mock systemctl 'exit 0'
mock rsync     'exit 0'
mock flock     'exit 0'
mock curl      'case "$*" in *unknown.invalid*) printf 404;; esac'
mock docker    'printf "%s\n" "$*" >> "$FIXTURE/docker-calls"
if [ "$1" = ps ] && [ "${RUNNING:-}" = tunnel ] && [ "$3" = "name=^/mushr-tunnel$" ]; then echo mushr-tunnel; fi
exit 0'

reset() {
  rm -rf "$WORK/var" "$WORK/docker-calls" "$WORK/deploy-calls"
}
restore() { # args...; sets out and status
  out="$(PATH="$MOCK_BIN:$PATH" FIXTURE="$WORK" bash "$SCRIPT" "$@" 2>&1)"
  status=$?
}

# ── default is a plan only ───────────────────────────────────────────────────
reset
restore
assert_eq "$status" 0 "plan succeeds"
assert_contains "$out" "LOFT_FORCE_DEPLOY=1" "plan shows forced deploys"
assert_contains "$out" "pawst-deploy.sh --no-verify hblake" "plan deploys each site unverified"
assert_missing "$WORK/docker-calls" "plan runs no docker commands"
assert_missing "$WORK/deploy-calls" "plan deploys nothing"
assert_missing "$WORK/var" "plan writes no state"

# ── tunnel gate ──────────────────────────────────────────────────────────────
reset
RUNNING=tunnel restore --apply
assert_fails "$status" "running tunnel blocks content restore"
assert_contains "$out" "Stop mushr-tunnel" "explains the tunnel gate"
assert_missing "$WORK/deploy-calls" "running tunnel prevents deploys"

# ── apply ────────────────────────────────────────────────────────────────────
reset
mkdir -p "$WORK/var/lib/loft/deploy"
echo -n old-release > "$WORK/var/lib/loft/deploy/pawst-hblake.version"
restore --apply
assert_eq "$status" 0 "apply succeeds"
mapfile -t calls < "$WORK/deploy-calls"
assert_eq "${#calls[@]}" 2 "deploys both sites"
assert_eq "$(grep -vc '^1|--no-verify ' "$WORK/deploy-calls")" 0 "every deploy is forced and unverified"
assert_eq "${calls[0]#*|}" "--no-verify hblake" "deploys hblake first"
assert_eq "${calls[1]#*|}" "--no-verify hsimah" "deploys hsimah second"
mapfile -t starts < <(grep 'up -d --wait' "$WORK/docker-calls")
assert_eq "${#starts[@]}" 2 "starts two services"
assert_eq "${starts[0]##*up -d --wait }" mushr "starts mushr first"
assert_eq "${starts[1]##*up -d --wait }" pawst "starts pawst second"
backups=("$WORK"/var/backups/loft/*/pawst-hblake.version)
assert_eq "${#backups[@]}" 1 "backs up the previous state once"
assert_file "${backups[0]}" old-release "backup holds the previous version"

finish
