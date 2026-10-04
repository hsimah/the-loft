#!/usr/bin/env bash
# test-onedrive-pull.sh — exercise the OneDrive puller's safety invariants
# against a mocked rclone, and check the Hubbl manifests agree on host paths.
# No Docker daemon, no network, no real rclone.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/control-plane/onedrive-pull.sh"
PASS=0
FAIL=0

ok()   { printf 'ok     %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf 'FAIL   %s\n     %s\n' "$1" "$2" >&2; FAIL=$((FAIL + 1)); }

assert_contains() { # haystack needle label
  case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "expected to find: $2" ;; esac
}
assert_absent() { # haystack needle label
  case "$1" in *"$2"*) bad "$3" "did not expect: $2" ;; *) ok "$3" ;; esac
}
assert_eq() { # actual expected label
  [[ "$1" == "$2" ]] && ok "$3" || bad "$3" "got '$1', wanted '$2'"
}

# ── Fixture ──────────────────────────────────────────────────────────────────
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
printf '[onedrive]\ntype = onedrive\n' > "$WORK/rclone.conf"

# Mock rclone: record its argv, optionally create a file, optionally fail.
cat > "$WORK/bin/rclone" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_ARGV"
if [ -n "${MOCK_RCLONE_CREATES:-}" ]; then
  mkdir -p "$3" && : > "$3/${MOCK_RCLONE_CREATES}"
fi
exit "${MOCK_RCLONE_EXIT:-0}"
MOCK
chmod +x "$WORK/bin/rclone"

run_pull() { # runs the puller in a clean state dir; echoes combined output
  local case_dir="$WORK/case-$1"; shift
  mkdir -p "$case_dir"
  MOCK_ARGV="$case_dir/argv" \
  PATH="$WORK/bin:$PATH" \
  ONEDRIVE_PULL_REMOTE="${REMOTE-onedrive:Pictures}" \
  ONEDRIVE_PULL_DEST="$case_dir/staging" \
  ONEDRIVE_PULL_CONFIG="${CONFIG-$WORK/rclone.conf}" \
  ONEDRIVE_PULL_STATE_DIR="$case_dir/state" \
  "$@" bash "$SCRIPT" 2>&1
}
argv_of() { cat "$WORK/case-$1/argv" 2>/dev/null || true; }

# ── copy, never sync ─────────────────────────────────────────────────────────
# sync propagates remote deletions onto the only local copy of the photos.
out="$(run_pull copy)"
argv="$(argv_of copy)"
assert_contains "$argv" "copy onedrive:Pictures" "uses rclone copy"
assert_absent   "$argv" "sync"                   "never uses rclone sync"
assert_contains "$argv" "--config"               "passes an explicit config"

# ── refuses to run without credentials ───────────────────────────────────────
out="$(CONFIG="$WORK/absent.conf" run_pull noconfig)"
assert_contains "$out" "No rclone config" "refuses a missing rclone config"
assert_eq "$(argv_of noconfig)" "" "does not invoke rclone without a config"

out="$(REMOTE="" run_pull noremote)"
assert_contains "$out" "ONEDRIVE_PULL_REMOTE is unset" "refuses an unset remote"
assert_eq "$(argv_of noremote)" "" "does not invoke rclone without a remote"

# ── concurrent ticks ─────────────────────────────────────────────────────────
# The first pull runs for hours while the 10-minute cron keeps firing.
mkdir -p "$WORK/case-locked/state"
LOCK="$WORK/case-locked/state/pull.lock"
: > "$LOCK"
flock "$LOCK" sleep 10 &
HOLDER=$!
flock --wait 5 "$LOCK" true   # block until the holder actually owns it
out="$(run_pull locked)"
rc=$?
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null
assert_eq "$rc" "0" "a contended tick exits cleanly"
assert_eq "$(argv_of locked)" "" "a contended tick does not pull"

# ── failures are not recorded as success ─────────────────────────────────────
out="$(run_pull failed env MOCK_RCLONE_EXIT=7)"
assert_contains "$out" "next tick resumes" "reports a resumable failure"
[[ -f "$WORK/case-failed/state/last-success" ]] \
  && bad "failure is not stamped as success" "last-success was written" \
  || ok "failure is not stamped as success"

# ── the drain-complete signal operators wait for ─────────────────────────────
out="$(run_pull done)"
assert_contains "$out" "Up to date" "reports an empty pull as up to date"
[[ -f "$WORK/case-done/state/last-success" ]] \
  && ok "stamps last-success after a clean run" \
  || bad "stamps last-success after a clean run" "no last-success file"

out="$(run_pull added env MOCK_RCLONE_CREATES=photo.jpg)"
assert_contains "$out" "Added 1 file(s)" "counts newly arrived files"

# ── manifests agree ──────────────────────────────────────────────────────────
conf="$(cat "${ROOT}/hosts/space-needle/host.conf")"
compose="$(cat "${ROOT}/services/hubbl/docker-compose.yml")"
for path in /opt/hubbl/db /mammoth/hubbl/library /mammoth/hubbl/staging; do
  assert_contains "$conf"    "$path" "host.conf provisions ${path}"
  assert_contains "$compose" "$path" "compose mounts ${path}"
done
# A repeated import must never be able to damage the source photos.
assert_contains "$compose" "/mammoth/hubbl/staging:/import:ro" "staging mounts read-only"

# Homepage drops any group that has no layout tab, silently and entirely.
groups="$(sed -nE 's/^- ([A-Za-z].*):$/\1/p' "${ROOT}/services/houstn/homepage-config/services.yaml" | sort -u)"
tabs="$(sed -n '/^layout:/,$p' "${ROOT}/services/houstn/homepage-config/settings.yaml" \
  | sed -nE 's/^  ([A-Za-z].*):$/\1/p' | sort -u)"
missing="$(comm -23 <(printf '%s\n' "$groups") <(printf '%s\n' "$tabs"))"
assert_eq "$missing" "" "every Homepage group declares a layout tab"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
