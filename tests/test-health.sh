#!/usr/bin/env bash
# test-health.sh — exercise common.sh's check_url and check_containers with
# mocked curl and docker. No Docker daemon, no network.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/tests/lib/assert.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/control-plane" "$WORK/hosts/test-host"
cp "${ROOT}/control-plane/common.sh" "$WORK/control-plane/"
echo "HOST_NAME=test-host" > "$WORK/hosts/test-host/host.conf"

MOCK_BIN="$WORK/bin"
mkdir -p "$MOCK_BIN"
mock hostname 'printf test-host'
mock curl     'printf "%s" "$MOCK_HTTP"; exit "$MOCK_CURL_EXIT"'
mock sleep    'exit 0'
mock docker   'case " $* " in
  *" config --services "*) printf "%s\n" "$MOCK_EXPECTED"; exit "${MOCK_CONFIG_EXIT:-0}" ;;
  *" ps --all --format "*) printf "%s\n" "$MOCK_STATES"; exit "${MOCK_PS_EXIT:-0}" ;;
  *" ps --all "*) exit 0 ;;
  *) echo "Unexpected Docker command: $*" >&2; exit 99 ;;
esac'

# Defaults: HTTP 200, two running services, db healthy. Override per call
# with VAR=value prefixes.
helper() { # command; sets out and status
  out="$(cd "$WORK" && PATH="$MOCK_BIN:$PATH" \
    MOCK_HTTP="${MOCK_HTTP-200}" MOCK_CURL_EXIT="${MOCK_CURL_EXIT-0}" \
    MOCK_EXPECTED="${MOCK_EXPECTED-$'web\ndb'}" \
    MOCK_STATES="${MOCK_STATES-$'web|running|\ndb|running|healthy'}" \
    timeout 5 bash -c "source control-plane/common.sh
HC_TIMEOUT=1
HC_INTERVAL=1
$1" 2>&1)"
  status=$?
}
CONTAINERS='check_containers "-f unused.yml" app'

# ── check_url ────────────────────────────────────────────────────────────────
MOCK_HTTP=000 MOCK_CURL_EXIT=7 helper "check_url http://unused local"
assert_eq "$status" 1 "connection failure fails"
assert_contains "$out" "FAIL" "connection failure reports FAIL"
assert_absent   "$out" "OK"   "connection failure never reports OK (000000)"

MOCK_HTTP=200 MOCK_CURL_EXIT=28 helper "check_url http://unused local"
assert_eq "$status" 1 "timeout after headers still fails"

MOCK_HTTP=000 MOCK_CURL_EXIT=7 helper "check_url http://unused local true"
assert_eq "$status" 0 "warn-only transport failure passes"
assert_contains "$out" "WARNING" "warn-only transport failure warns"

MOCK_HTTP=000 helper "check_url http://unused local"
assert_eq "$status" 1 "HTTP 000 without a transport error is not a response"

for code in 200 302 401 403 502; do
  MOCK_HTTP=$code helper "check_url http://unused local"
  assert_eq "$status" 0 "HTTP ${code} counts as reachable"
  assert_contains "$out" "HTTP ${code}" "HTTP ${code} is reported"
done

# ── check_containers ─────────────────────────────────────────────────────────
helper "$CONTAINERS"
assert_eq "$status" 0 "running services with optional healthchecks pass"

MOCK_STATES='web|running|' helper "$CONTAINERS"
assert_eq "$status" 1 "missing active service fails"

MOCK_STATES=$'web|running|\ndb|running|healthy\ncli|exited|' helper "$CONTAINERS"
assert_eq "$status" 0 "inactive CLI container does not fail active services"

for state in 'db|exited|' 'db|running|starting' 'db|running|unhealthy'; do
  MOCK_STATES=$'web|running|\n'"$state" helper "$CONTAINERS"
  assert_eq "$status" 1 "service state ${state#db|} fails"
done

MOCK_EXPECTED=web MOCK_STATES=$'web|running|healthy\nweb|exited|' helper "$CONTAINERS"
assert_eq "$status" 1 "failed replica is not hidden by a healthy one"

MOCK_EXPECTED='' helper "$CONTAINERS"
assert_eq "$status" 1 "empty service selection fails"

MOCK_CONFIG_EXIT=1 helper "$CONTAINERS"
assert_eq "$status" 1 "docker compose config error fails"
MOCK_PS_EXIT=1 helper "$CONTAINERS"
assert_eq "$status" 1 "docker compose ps error fails"

finish
