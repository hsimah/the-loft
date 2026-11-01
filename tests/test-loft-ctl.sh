#!/usr/bin/env bash
# test-loft-ctl.sh — loft-ctl start/stop/rebuild must report failure when
# docker compose fails (set -e is off inside functions called with ||).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/tests/lib/assert.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
LC="$WORK/lc"
mkdir -p "$LC/control-plane" "$LC/hosts/test-host" "$LC/services/web"
cp "${ROOT}/loft-ctl" "$LC/loft-ctl"
cp "${ROOT}/control-plane/common.sh" "$LC/control-plane/"
printf 'HOST_NAME=test-host\nSERVICES=(web)\n' > "$LC/hosts/test-host/host.conf"
touch "$LC/services/web/docker-compose.yml"

MOCK_BIN="$WORK/bin"
mkdir -p "$MOCK_BIN"
mock hostname 'printf test-host'
# Compose fails for the subcommand named in FAIL_ON ("up" or "down").
mock docker 'case " $* " in *" $FAIL_ON "*) echo "Address already in use" >&2; exit 1 ;; esac; exit 0'

run() { # args...; sets out and status
  out="$(PATH="$MOCK_BIN:$PATH" bash "$LC/loft-ctl" "$@" 2>&1)"
  status=$?
}

FAIL_ON=none run start web
assert_eq "$status" 0 "start succeeds when compose succeeds"
assert_contains "$out" "Started web." "start reports success"

export FAIL_ON=up
run start web
assert_fails "$status" "start exits non-zero when compose up fails"
assert_absent "$out" "Started web." "start does not claim success"
assert_absent "$out" "all operations succeeded" "summary does not claim success"

run rebuild web
assert_fails "$status" "rebuild exits non-zero when compose up fails"
assert_absent "$out" "Rebuilt web." "rebuild does not claim success"

export FAIL_ON=down
run stop web
assert_fails "$status" "stop exits non-zero when compose down fails"
assert_absent "$out" "Stopped web." "stop does not claim success"

finish
