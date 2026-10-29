#!/usr/bin/env bash
# test-mercurius-vault.sh — the vault script must never create Mercurius's
# directories outside the unlocked volume, and must not lock under a running
# group. Also checks the manifests keep every Mercurius bind inside /mercurius.
# Mocked cryptsetup, findmnt, mount, umount and docker; no root, no devices.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/control-plane/mercurius-vault.sh"
source "${ROOT}/tests/lib/assert.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
MOCK_BIN="$WORK/bin"
mkdir -p "$MOCK_BIN"

# Mock state lives in $STATE: `open` while the mapping exists, `mounted` holds
# the source mounted at the vault's mount point, `calls` logs every call.
mock cryptsetup 'echo "cryptsetup $*" >> "$STATE/calls"
case "$1" in
  status) [ -e "$STATE/open" ] ;;
  open)   [ "${MOCK_OPEN_EXIT:-0}" = 0 ] && touch "$STATE/open" ;;
  close)  rm -f "$STATE/open" ;;
esac'
mock findmnt 'cat "$STATE/mounted" 2>/dev/null'
mock mount 'echo "mount $*" >> "$STATE/calls"
[ "${MOCK_MOUNT_EXIT:-0}" = 0 ] && printf "%s\n" "$1" > "$STATE/mounted"'
mock umount 'echo "umount $*" >> "$STATE/calls"; rm -f "$STATE/mounted"'
mock docker 'printf "%s" "${MOCK_RUNNING:-}"'

run_vault() { # case action; echoes combined output, returns the script's status
  local case_dir="$WORK/$1"
  mkdir -p "$case_dir/state"
  : > "$case_dir/lv"
  STATE="$case_dir/state" \
  PATH="$MOCK_BIN:$PATH" \
  MERCURIUS_DEVICE="$case_dir/lv" \
  MERCURIUS_MAPPER_DEV="/dev/mapper/mercurius" \
  MERCURIUS_MOUNT="$case_dir/mercurius" \
  MERCURIUS_OWNER="$(id -un):$(id -gn)" \
  MERCURIUS_REQUIRE_ROOT=0 \
  bash "$SCRIPT" "$2" 2>&1
}
calls_of() { cat "$WORK/$1/state/calls" 2>/dev/null || true; }

# ── locked → unlock opens, mounts, then creates the directories ──────────────
out="$(run_vault fresh unlock)"; status=$?
assert_eq "$status" 0 "unlock succeeds from locked"
calls="$(calls_of fresh)"
assert_contains "$calls" "cryptsetup open" "opens the LUKS volume"
assert_contains "$calls" "mount /dev/mapper/mercurius" "mounts the mapped device"
for d in data media consume export gpt/config gpt/db gpt/prompts silverbullet db redis; do
  [[ -d "$WORK/fresh/mercurius/$d" ]] && ok "creates $d inside the vault" || bad "creates $d inside the vault" "missing"
done
assert_eq "$(stat -c %a "$WORK/fresh/mercurius/db")" 755 "Postgres can traverse the db directory"

# ── already unlocked → no second open or mount ───────────────────────────────
mkdir -p "$WORK/again/state"
touch "$WORK/again/state/open"
echo /dev/mapper/mercurius > "$WORK/again/state/mounted"
out="$(run_vault again unlock)"; status=$?
assert_eq "$status" 0 "unlock is idempotent"
assert_absent "$(calls_of again)" "cryptsetup open" "does not reopen an open volume"
assert_absent "$(calls_of again)" "mount " "does not remount"

# ── wrong passphrase → nothing mounted, nothing created ──────────────────────
out="$(MOCK_OPEN_EXIT=1 run_vault badpass unlock)"; status=$?
assert_fails "$status" "unlock fails when cryptsetup open fails"
assert_absent "$(calls_of badpass)" "mount " "never mounts a volume it could not open"
assert_missing "$WORK/badpass/mercurius/data" "creates no directories"

# ── mount fails → no directories on the bare mount point ─────────────────────
out="$(MOCK_MOUNT_EXIT=1 run_vault nomount unlock)"; status=$?
assert_fails "$status" "unlock fails when mount fails"
assert_missing "$WORK/nomount/mercurius/data" "no directories on the unencrypted mount point"

# ── something else mounted there → refuse ────────────────────────────────────
mkdir -p "$WORK/other/state"
echo /dev/sdz1 > "$WORK/other/state/mounted"
out="$(run_vault other unlock)"; status=$?
assert_fails "$status" "refuses when another device is mounted there"
assert_contains "$out" "not the vault" "names the problem"
assert_missing "$WORK/other/mercurius/data" "creates nothing on the other device"

# ── lock refuses while Mercurius runs ────────────────────────────────────────
mkdir -p "$WORK/busy/state"
touch "$WORK/busy/state/open"
echo /dev/mapper/mercurius > "$WORK/busy/state/mounted"
out="$(MOCK_RUNNING=abc123 run_vault busy lock)"; status=$?
assert_fails "$status" "lock refuses while Mercurius is running"
assert_absent "$(calls_of busy)" "umount" "does not unmount under a running Mercurius"

# ── lock when stopped → unmount and close ────────────────────────────────────
mkdir -p "$WORK/idle/state"
touch "$WORK/idle/state/open"
echo /dev/mapper/mercurius > "$WORK/idle/state/mounted"
out="$(run_vault idle lock)"; status=$?
assert_eq "$status" 0 "lock succeeds when Mercurius is stopped"
assert_contains "$(calls_of idle)" "umount" "unmounts"
assert_contains "$(calls_of idle)" "cryptsetup close mercurius" "closes the mapping"

# ── manifests ────────────────────────────────────────────────────────────────
conf="$(cat "${ROOT}/hosts/space-needle/host.conf")"
dirs="$(sed -n '/^CONFIG_DIRS=(/,/^)/p; /^MEDIA_DIRS=(/,/^)/p' "${ROOT}/hosts/space-needle/host.conf")"
assert_absent "$dirs" "/mercurius" "setup never creates vault directories on the plain disk"
assert_contains "$conf" '[mercurius]="/mercurius"' "setup waits for the vault mount"

compose="$(cat "${ROOT}/services/mercurius/docker-compose.yml")"
sources="$(grep -c 'source: /mercurius/' <<< "$compose")"
no_create="$(grep -c 'create_host_path: false' <<< "$compose")"
assert_eq "$sources" 10 "ten binds, all inside /mercurius"
assert_eq "$no_create" "$sources" "no bind creates its source"
assert_absent "$(grep -E '^\s+- /' <<< "$compose")" "/" "no short-syntax binds"
assert_contains "$compose" "internal: true" "the group's own network has no route out"

finish
