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

# A failed pull or build stops the rebuild before the running service is taken down.
mock docker "echo \"\$*\" >> '$WORK/calls'; "'case " $* " in *" $FAIL_ON "*) echo "pull access denied" >&2; exit 1 ;; esac; exit 0'
for step in pull build; do
  : > "$WORK/calls"
  FAIL_ON=$step run rebuild web
  assert_fails "$status" "rebuild exits non-zero when compose $step fails"
  assert_contains "$out" "still running" "rebuild reports the $step failure"
  assert_absent "$(cat "$WORK/calls")" " down" "rebuild does not stop the service after a failed $step"
done

: > "$WORK/calls"
FAIL_ON=none run rebuild web
assert_eq "$status" 0 "rebuild succeeds when compose succeeds"
assert_eq "$(grep -oE ' (pull|build|down|up)( |$)' "$WORK/calls" | tr -d ' ' | paste -sd' ')" "pull build down up" \
  "rebuild pulls and builds before down"
assert_contains "$(cat "$WORK/calls")" "pull --ignore-buildable" "rebuild skips pulling local builds"
mock docker 'case " $* " in *" $FAIL_ON "*) echo "Address already in use" >&2; exit 1 ;; esac; exit 0'

export FAIL_ON=down
run stop web
assert_fails "$status" "stop exits non-zero when compose down fails"
assert_absent "$out" "Stopped web." "stop does not claim success"

# setup hands off to the repo's setup.sh (which elevates itself).
printf 'echo "setup ran"\n' > "$LC/control-plane/setup.sh"
run setup
assert_eq "$status" 0 "setup succeeds"
assert_contains "$out" "setup ran" "setup runs setup.sh"
run setup web
assert_fails "$status" "setup rejects arguments"
assert_absent "$out" "setup ran" "rejected setup does not provision"

finish
