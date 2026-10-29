#!/usr/bin/env bash
# loft-backup.sh — encrypted off-site backups: restic to Google Drive through rclone.
#
#   loft-backup init               # create the restic repositories (once)
#   loft-backup backup [job...]    # nightly; default: every job in BACKUP_JOBS
#   loft-backup check              # weekly: prune, verify, and flag stale jobs
#
# Installed by setup.sh to /usr/local/bin/loft-backup and run by systemd timers.
# Configuration comes from /etc/default/loft-backup (BACKUP_* — from host.conf).
#
# Two repositories with two passwords. The vault repository holds Mercurius
# (Paperless and the wiki) only; its password file lives inside the vault, so
# nothing here can read vault backups while /mercurius is locked, and a stolen
# root disk cannot decrypt them. The open repository holds Forgejo.
#   docs/operations/backups.md
set -uo pipefail

# Timers run with a minimal PATH; restic and rclone may be in /usr/local/bin.
PATH="${PATH}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

: "${BACKUP_REMOTE:=}"
: "${BACKUP_JOBS:=mercurius forgejo}"
: "${BACKUP_RCLONE_CONFIG:=/etc/loft/rclone/gdrive.conf}"
: "${BACKUP_OPEN_PASSWORD_FILE:=/etc/loft/restic/open.pass}"
: "${BACKUP_STATE_DIR:=/var/lib/loft/backup}"
: "${BACKUP_NTFY_URL:=}"
: "${BACKUP_PUSH_FILE:=/etc/loft/backup-push}"
: "${BACKUP_CHECK_SUBSET:=5%}"
: "${BACKUP_MAX_AGE_DAYS:=3}"
: "${BACKUP_HOST:=$(hostname)}"
: "${BACKUP_REQUIRE_ROOT:=1}"

: "${MERCURIUS_MOUNT:=/mercurius}"
: "${MERCURIUS_MAPPER_DEV:=/dev/mapper/mercurius}"
: "${FORGEJO_CONFIG_DIR:=/opt/kennl/forgejo/config}"

# The vault's password file sits on the vault; backup/stage holds the export
# and database dump so no plaintext copy of either reaches the plain disk.
VAULT_BACKUP_DIR="${MERCURIUS_MOUNT}/backup"
VAULT_STAGE_DIR="${VAULT_BACKUP_DIR}/stage"
: "${BACKUP_VAULT_PASSWORD_FILE:=${VAULT_BACKUP_DIR}/restic.pass}"

# Open-zone staging is plaintext on the root disk, removed after every run.
OPEN_STAGE_DIR="${BACKUP_STATE_DIR}/stage"
CACHE_DIR="${BACKUP_STATE_DIR}/cache"
LOCK_FILE="${BACKUP_STATE_DIR}/backup.lock"

# Skipped is not a failure: a locked vault is the normal state after a reboot.
RC_SKIP=2

log() { echo "[$(date -Is)] $*"; }
die() { log "ERROR: $*"; exit 1; }

notify() { # message
  [[ -n "$BACKUP_NTFY_URL" ]] || return 0
  curl -fsS -m 20 -H "Title: Backup failed on ${BACKUP_HOST}" -H "Priority: high" \
    -H "Tags: warning" -d "$1" "$BACKUP_NTFY_URL" > /dev/null 2>&1 \
    || log "could not reach ntfy at ${BACKUP_NTFY_URL}"
}

# Report a job to its Uptime Kuma push monitor, which Homepage's Backups tile
# reads. BACKUP_PUSH_FILE holds one "<job> <push URL>" per line (the URLs carry
# tokens, so the file stays out of the repo). A skipped job pushes nothing: its
# monitor goes down when the heartbeat interval lapses, which is the alarm for
# a vault left locked.
push() { # job up|down
  local url
  [[ -r "$BACKUP_PUSH_FILE" ]] || return 0
  url="$(awk -v j="$1" '$1 == j { print $2; exit }' "$BACKUP_PUSH_FILE")"
  [[ -n "$url" ]] || return 0
  curl -fsS -m 20 "${url}?status=${2}&msg=$([[ "$2" == up ]] && echo OK || echo FAILED)" > /dev/null 2>&1 \
    || log "could not reach Uptime Kuma for ${1}"
}

vault_unlocked() {
  [[ "$(findmnt -n -o SOURCE --mountpoint "$MERCURIUS_MOUNT" 2> /dev/null || true)" == "$MERCURIUS_MAPPER_DEV" ]]
}

job_repo() { # job → vault|open
  case "$1" in
    mercurius) echo vault ;;
    forgejo) echo open ;;
    *) return 1 ;;
  esac
}

password_file() { # vault|open
  if [[ "$1" == vault ]]; then echo "$BACKUP_VAULT_PASSWORD_FILE"; else echo "$BACKUP_OPEN_PASSWORD_FILE"; fi
}

# rs <vault|open> <restic args...>
rs() {
  local repo="$1"
  shift
  RESTIC_REPOSITORY="rclone:${BACKUP_REMOTE}/${repo}" \
    RESTIC_PASSWORD_FILE="$(password_file "$repo")" \
    RESTIC_CACHE_DIR="$CACHE_DIR" \
    RCLONE_CONFIG="$BACKUP_RCLONE_CONFIG" \
    restic "$@"
}

# Run a command with stdout to a file; the file is kept only if it succeeds
# and is not empty, so a failed dump can never be backed up as if it were whole.
dump_to() { # file command...
  local out="$1"
  shift
  if "$@" > "${out}.partial" && [[ -s "${out}.partial" ]]; then
    mv "${out}.partial" "$out"
  else
    rm -f "${out}.partial"
    return 1
  fi
}

# Daily/weekly/monthly as in the backups plan; the vault also keeps every year.
forget() { # vault|open job
  local keep=(--keep-daily 7 --keep-weekly 4 --keep-monthly 12)
  [[ "$1" == vault ]] && keep+=(--keep-yearly unlimited)
  rs "$1" forget --tag "$2" --group-by host,tags "${keep[@]}"
}

# ── Jobs ─────────────────────────────────────────────────────────────────────

job_mercurius() {
  if ! vault_unlocked; then
    log "mercurius: vault is locked; skipping"
    return "$RC_SKIP"
  fi
  [[ -s "$BACKUP_VAULT_PASSWORD_FILE" ]] || { log "mercurius: no password file at ${BACKUP_VAULT_PASSWORD_FILE}"; return 1; }
  # An empty wiki folder on an unlocked vault means the data is gone; a
  # snapshot of it would only push good snapshots out of retention.
  [[ -n "$(ls -A "${MERCURIUS_MOUNT}/silverbullet" 2> /dev/null)" ]] \
    || { log "mercurius: ${MERCURIUS_MOUNT}/silverbullet is missing or empty"; return 1; }

  install -d -m 700 "$VAULT_BACKUP_DIR" "$VAULT_STAGE_DIR" || return 1

  # Exporter output is portable across Paperless versions; -d keeps the export
  # directory an exact copy of the archive, so it is only ever this job's.
  log "mercurius: exporting documents"
  docker exec paperless document_exporter /usr/src/paperless/export -c -d --no-progress-bar || return 1

  # The importer wants the Paperless version that exported; the snapshot says which.
  docker inspect --format '{{.Config.Image}}' paperless > "${VAULT_STAGE_DIR}/paperless-image.txt" || return 1

  log "mercurius: dumping Postgres"
  dump_to "${VAULT_STAGE_DIR}/paperless.dump" \
    docker exec mercurius-db sh -c 'pg_dump -U "$POSTGRES_USER" -Fc "$POSTGRES_DB"' || return 1

  # The wiki folder is copied live, its .git (the page revisions) included.
  log "mercurius: backing up"
  rs vault backup --host "$BACKUP_HOST" --tag mercurius \
    "${MERCURIUS_MOUNT}/export" "$VAULT_STAGE_DIR" "${MERCURIUS_MOUNT}/silverbullet" || return 1
  forget vault mercurius
}

job_forgejo() {
  local rc=0
  install -d -m 700 "$OPEN_STAGE_DIR" || return 1
  rm -rf "${OPEN_STAGE_DIR:?}/forgejo"
  install -d -m 700 "${OPEN_STAGE_DIR}/forgejo" || return 1

  log "forgejo: dumping"
  dump_to "${OPEN_STAGE_DIR}/forgejo/forgejo-dump.tar" \
    docker exec forgejo forgejo dump --file - --type tar \
    && dump_to "${OPEN_STAGE_DIR}/forgejo/forgejo-db.dump" \
      docker exec kennl-db sh -c 'pg_dump -U "$POSTGRES_USER" -Fc "$POSTGRES_DB"' \
    && cp -p "${FORGEJO_CONFIG_DIR}/app.ini" "${OPEN_STAGE_DIR}/forgejo/app.ini" \
    || rc=1

  if [[ "$rc" -eq 0 ]]; then
    log "forgejo: backing up"
    rs open backup --host "$BACKUP_HOST" --tag forgejo "${OPEN_STAGE_DIR}/forgejo" || rc=1
    [[ "$rc" -eq 0 ]] && { forget open forgejo || rc=1; }
  fi
  rm -rf "${OPEN_STAGE_DIR:?}/forgejo"
  return "$rc"
}

# ── Commands ─────────────────────────────────────────────────────────────────

mark_success() { date -Is > "${BACKUP_STATE_DIR}/last-success.$1"; }

run_backup() {
  local jobs=("$@") job rc failed=()
  [[ ${#jobs[@]} -gt 0 ]] || read -r -a jobs <<< "$BACKUP_JOBS"

  for job in "${jobs[@]}"; do
    job_repo "$job" > /dev/null || die "unknown job: ${job}"
  done

  for job in "${jobs[@]}"; do
    "job_${job}"
    rc=$?
    case "$rc" in
      0) mark_success "$job"; log "${job}: done"; push "$job" up ;;
      "$RC_SKIP") ;;
      *) log "${job}: FAILED"; failed+=("$job"); push "$job" down ;;
    esac
  done

  if [[ ${#failed[@]} -gt 0 ]]; then
    notify "Backup failed: ${failed[*]}. See: journalctl -u loft-backup"
    return 1
  fi
}

run_check() {
  local job repo rc failed=() stale=() repos=() last age_limit
  local seen=" "

  for job in $BACKUP_JOBS; do
    repo="$(job_repo "$job")" || die "unknown job: ${job}"
    [[ "$seen" == *" $repo "* ]] || { seen+="${repo} "; repos+=("$repo"); }
  done

  for repo in "${repos[@]}"; do
    if [[ "$repo" == vault ]] && ! vault_unlocked; then
      log "vault: locked; skipping check"
      continue
    fi
    log "${repo}: pruning and checking"
    rs "$repo" prune && rs "$repo" check --read-data-subset "$BACKUP_CHECK_SUBSET" \
      || { log "${repo}: FAILED"; failed+=("$repo"); }
  done

  # A job that has skipped or failed for days leaves no recent snapshot, and
  # skipping is silent by design. Say so here.
  age_limit="$BACKUP_MAX_AGE_DAYS"
  for job in $BACKUP_JOBS; do
    last="${BACKUP_STATE_DIR}/last-success.${job}"
    if [[ ! -f "$last" ]] || [[ -n "$(find "$last" -mtime "+${age_limit}" 2> /dev/null)" ]]; then
      log "${job}: no successful backup in ${age_limit} days"
      stale+=("$job")
    fi
  done

  rc=0
  if [[ ${#failed[@]} -gt 0 ]]; then
    notify "Repository check failed: ${failed[*]}. See: journalctl -u loft-backup-check"
    rc=1
  fi
  if [[ ${#stale[@]} -gt 0 ]]; then
    notify "No recent backup for: ${stale[*]} (vault locked since a reboot?)"
    rc=1
  fi
  # Stale jobs report through their own monitors lapsing; "check" reports the
  # repositories themselves.
  if [[ ${#failed[@]} -gt 0 ]]; then push check down; else push check up; fi
  return "$rc"
}

run_init() {
  local job repo seen=" "
  for job in $BACKUP_JOBS; do
    repo="$(job_repo "$job")" || die "unknown job: ${job}"
    [[ "$seen" == *" $repo "* ]] && continue
    seen+="${repo} "
    if [[ "$repo" == vault ]]; then
      vault_unlocked || die "unlock the vault first (the vault repository's password file is inside it)"
      install -d -m 700 "$VAULT_BACKUP_DIR" || die "cannot create ${VAULT_BACKUP_DIR}"
    fi
    [[ -s "$(password_file "$repo")" ]] || die "no password file at $(password_file "$repo")"
    if rs "$repo" cat config > /dev/null 2>&1; then
      log "${repo}: repository already exists"
    else
      rs "$repo" init || die "${repo}: could not initialise rclone:${BACKUP_REMOTE}/${repo}"
    fi
  done
}

# ── Main ─────────────────────────────────────────────────────────────────────

cmd="${1:-}"
shift || true
case "$cmd" in
  init | backup | check) ;;
  *) die "usage: loft-backup init | backup [job...] | check" ;;
esac

[[ "$BACKUP_REQUIRE_ROOT" != 1 || "$EUID" -eq 0 ]] || die "run with sudo"
[[ -n "$BACKUP_REMOTE" ]] || die "BACKUP_REMOTE is unset"
[[ -r "$BACKUP_RCLONE_CONFIG" ]] \
  || die "no rclone config at ${BACKUP_RCLONE_CONFIG} (see docs/operations/backups.md)"
for tool in restic flock docker; do
  command -v "$tool" > /dev/null || die "${tool} is not installed"
done

install -d -m 700 "$BACKUP_STATE_DIR" "$CACHE_DIR" || die "cannot create ${BACKUP_STATE_DIR}"

# One run at a time: the weekly prune must not overlap a backup.
exec 9> "$LOCK_FILE"
if ! flock -n 9; then
  log "another loft-backup run is in progress; exiting"
  exit 0
fi

"run_${cmd}" "$@"
