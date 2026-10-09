#!/usr/bin/env bash
# test-production-setup.sh — run setup.sh's real docker-membership section
# with mocked account-management commands.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/tests/lib/assert.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
MOCK_BIN="$WORK/bin"
mkdir -p "$MOCK_BIN"
mock id      'printf "%s\n" "$MOCK_GROUPS"'
mock gpasswd 'printf "gpasswd %s\n" "$*"; exit "$MOCK_REMOVE_STATUS"'
mock usermod 'printf "usermod %s\n" "$*"'

# From the line after the section's comment up to the next section header.
SECTION="$(sed -n '/^# Ensure docker group memberships;/,/^# ─── 10a\./{//!p}' "${ROOT}/setup.sh")"

membership() { # production [groups] [gpasswd-status]; sets out and status
  out="$(PATH="$MOCK_BIN:$PATH" PRODUCTION_ROLE="$1" MOCK_GROUPS="${2-pack-member docker}" \
    MOCK_REMOVE_STATUS="${3:-0}" bash -c "set -euo pipefail
$SECTION" 2>&1)"
  status=$?
}

membership true
assert_eq "$status" 0 "production membership succeeds"
assert_contains "$out" "gpasswd -d littledog docker"   "production removes legacy littledog access"
assert_absent   "$out" "usermod -aG docker littledog"  "production does not re-add littledog"
assert_contains "$out" "usermod -aG docker adminhabl"  "production keeps adminhabl"

membership true pack-member
assert_eq "$status" 0 "production is idempotent without membership"
assert_absent "$out" "gpasswd"   "no removal when littledog is not a member"
assert_absent "$out" "littledog" "littledog untouched when not a member"

membership false
assert_eq "$status" 0 "non-production membership succeeds"
assert_contains "$out" "usermod -aG docker littledog" "non-production adds littledog"
assert_contains "$out" "usermod -aG docker adminhabl" "non-production adds adminhabl"

membership true "pack-member docker" 1
assert_fails "$status" "failed removal stops setup"
assert_absent "$out" "usermod" "nothing runs after a failed removal"

finish
