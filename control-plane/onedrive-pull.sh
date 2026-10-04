#!/usr/bin/env bash
# onedrive-pull.sh — incrementally mirror a OneDrive folder into a local
# staging directory with rclone, safe to run every few minutes from cron.
#
# Installed by setup.sh to /usr/local/bin/loft-onedrive-pull and invoked by
# /etc/cron.d/loft-onedrive-pull. Configuration is sourced from
# /etc/default/loft-onedrive-pull (ONEDRIVE_PULL_* — all from host.conf).
#
# This is migration scaffolding, not a permanent fleet service: it exists to
# drain a OneDrive account into /mammoth/hubbl/staging so the photos can be
# imported into Hubbl. Set ONEDRIVE_PULL_ENABLED="false" in host.conf and
# re-run setup.sh to remove the cron entry once OneDrive is off.
#
#   docs/operations/onedrive-migration.md
set -uo pipefail

# Cron's PATH omits /usr/local/bin on some distributions, which is exactly
# where a manually installed rclone lands. Appended rather than assigned so an
# operator (or the test suite) can still put a directory in front.
PATH="${PATH}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

: "${ONEDRIVE_PULL_REMOTE:=}"
: "${ONEDRIVE_PULL_DEST:=}"
: "${ONEDRIVE_PULL_CONFIG:=/etc/loft/rclone/rclone.conf}"
: "${ONEDRIVE_PULL_BWLIMIT:=}"
: "${ONEDRIVE_PULL_TRANSFERS:=4}"
: "${ONEDRIVE_PULL_TPSLIMIT:=10}"
: "${ONEDRIVE_PULL_OWNER:=littledog:pack-member}"

STATE_DIR="${ONEDRIVE_PULL_STATE_DIR:-/var/lib/loft/onedrive-pull}"
LOCK_FILE="${STATE_DIR}/pull.lock"

log() { echo "[$(date -Is)] $*"; }
die() { log "ERROR: $*"; exit 1; }

[[ -n "$ONEDRIVE_PULL_REMOTE" ]] || die "ONEDRIVE_PULL_REMOTE is unset"
[[ -n "$ONEDRIVE_PULL_DEST"   ]] || die "ONEDRIVE_PULL_DEST is unset"

command -v rclone >/dev/null || die "rclone is not installed"
command -v flock  >/dev/null || die "flock is not installed"

# The config holds a refresh token for the OneDrive account. rclone rewrites
# it in place as tokens roll over, so it must stay writable by this user.
[[ -r "$ONEDRIVE_PULL_CONFIG" ]] \
  || die "No rclone config at ${ONEDRIVE_PULL_CONFIG} (see docs/operations/onedrive-migration.md)"

mkdir -p "$STATE_DIR" "$ONEDRIVE_PULL_DEST"

# ── Single-runner guard ──────────────────────────────────────────────────────
# The first pull of a full photo library runs for hours while the cron keeps
# firing every few minutes. Take the lock non-blockingly and leave quietly if
# a pull is already in flight; the next tick will find it finished.
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  exit 0
fi

# ── Pull ─────────────────────────────────────────────────────────────────────
# `copy`, never `sync`: sync propagates remote deletions to the local side, so
# a mistyped remote path or a half-migrated OneDrive folder would delete the
# staging copy of photos already drained off the account. copy only ever adds.
#
# --retries 1 because cron is the retry loop — a throttled or interrupted run
# should surrender the lock and let the next tick resume, not sit in rclone's
# own backoff and block ticks behind it.
opts=(
  --config "$ONEDRIVE_PULL_CONFIG"
  --transfers "$ONEDRIVE_PULL_TRANSFERS"
  --checkers 8
  --tpslimit "$ONEDRIVE_PULL_TPSLIMIT"
  --retries 1
  --low-level-retries 5
  --stats-one-line
  --stats 5m
  --exclude "desktop.ini"
  --exclude ".DS_Store"
  --exclude "**/.thumbnails/**"
)
[[ -n "$ONEDRIVE_PULL_BWLIMIT" ]] && opts+=(--bwlimit "$ONEDRIVE_PULL_BWLIMIT")

log "Pulling ${ONEDRIVE_PULL_REMOTE} -> ${ONEDRIVE_PULL_DEST}"

rclone copy "$ONEDRIVE_PULL_REMOTE" "$ONEDRIVE_PULL_DEST" "${opts[@]}" 2>&1
rc=$?

# Counting the tree is the only honest way to report progress, but it is a
# full stat walk of six figures of photos on the same volume Plex reads from.
# Carry the previous total in the state dir so each tick walks once, not twice.
COUNT_FILE="${STATE_DIR}/file-count"
before=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
[[ "$before" =~ ^[0-9]+$ ]] || before=0
after=$(find "$ONEDRIVE_PULL_DEST" -type f 2>/dev/null | wc -l)
printf '%s\n' "$after" > "$COUNT_FILE"
added=$(( after - before ))

# Photos land root-owned under cron; the import container and any manual
# inspection run as the service account. Only when something actually arrived
# — a recursive chown over a six-figure photo tree every ten minutes is a lot
# of pointless I/O on the same spindle Plex is reading from.
if (( added > 0 )); then
  chown -R "$ONEDRIVE_PULL_OWNER" "$ONEDRIVE_PULL_DEST" 2>/dev/null || true
fi

if (( rc != 0 )); then
  log "rclone exited ${rc} after adding ${added} file(s); next tick resumes"
  exit "$rc"
fi

date -Is > "${STATE_DIR}/last-success"
if (( added <= 0 )); then
  # The signal the operator is waiting for: OneDrive has nothing left to give.
  # Confirm it repeats across a few ticks before turning the account off.
  # (A negative delta means files left staging locally, not that any arrived.)
  log "Up to date — 0 new files, ${after} total in staging"
else
  log "Added ${added} file(s); ${after} total in staging"
fi
