#!/usr/bin/env bash
# test-backup.sh — exercise loft-backup's invariants against mocked restic,
# docker, findmnt and curl: separate repositories and passwords, nothing
# unencrypted staged for the vault, a clean skip while it is locked, retention,
# failure isolation and notification. No Docker daemon, no network, no root.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/control-plane/loft-backup.sh"
source "${ROOT}/tests/lib/assert.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
MOCK_BIN="$WORK/bin"
mkdir -p "$MOCK_BIN"
printf '[gdrive]\ntype = drive\n' > "$WORK/gdrive.conf"

# Every mock appends to $CALLS. restic also records which repository and
# password file it was given, since mixing them is the failure that matters.
RESTIC_MOCK='echo "repo=$RESTIC_REPOSITORY pass=$RESTIC_PASSWORD_FILE rclone=$RCLONE_CONFIG :: $*" >> "$CALLS"
case "$*" in *"cat config"*) exit "${MOCK_RESTIC_HAS_REPO:-0}" ;; esac
if [ -n "${MOCK_RESTIC_FAIL_ON:-}" ]; then case "$*" in *"$MOCK_RESTIC_FAIL_ON"*) exit 1 ;; esac; fi
exit 0'
mock restic "$RESTIC_MOCK"
mock docker 'echo "docker $*" >> "$CALLS"
if [ -n "${MOCK_DOCKER_FAIL_ON:-}" ]; then case "$*" in *"$MOCK_DOCKER_FAIL_ON"*) exit 1 ;; esac; fi
case "$*" in
  *inspect*)        echo "ghcr.io/paperless-ngx/paperless-ngx:3.3.4" ;;
  *pg_dump*)        echo "pgdump-bytes" ;;
  *"forgejo dump"*) echo "dump-bytes" ;;
esac
exit 0'
mock findmnt 'printf "%s\n" "${MOCK_MOUNT_SRC:-}"'
mock curl 'echo "curl $*" >> "$CALLS"'

UNLOCKED="/dev/mapper/mercurius"

# run_case <case> "<loft-backup args>" [VAR=value...]
# Each case gets its own plain-disk state, fake /mercurius and fake data folders.
# Sets out (combined output), rc and CASE (the case directory).
run_case() {
  local c="$WORK/$1" args="$2"
  shift 2
  mkdir -p "$c/mercurius/backup" "$c/mercurius/silverbullet" "$c/forgejo-config" "$c/etc"
  # EMPTY_WIKI=1 leaves the wiki folder empty.
  [[ -n "${EMPTY_WIKI:-}" ]] \
    || { mkdir -p "$c/mercurius/silverbullet/spaces"; echo note > "$c/mercurius/silverbullet/spaces/page.md"; }
  echo "[server]" > "$c/forgejo-config/app.ini"
  echo open-pw > "$c/etc/open.pass"
  echo vault-pw > "$c/mercurius/backup/restic.pass"
  : > "$c/calls"
  # shellcheck disable=SC2086
  out="$(env CALLS="$c/calls" PATH="$MOCK_BIN:$PATH" \
    BACKUP_REQUIRE_ROOT=0 \
    BACKUP_REMOTE="gdrive:the-loft" \
    BACKUP_RCLONE_CONFIG="$WORK/gdrive.conf" \
    BACKUP_OPEN_PASSWORD_FILE="$c/etc/open.pass" \
    BACKUP_STATE_DIR="$c/state" \
    BACKUP_HOST="space-needle" \
    BACKUP_NTFY_URL="https://ntfy.test/loft-backup" \
    BACKUP_PUSH_FILE="$c/no-push-file" \
    MERCURIUS_MOUNT="$c/mercurius" \
    MERCURIUS_MAPPER_DEV="$UNLOCKED" \
    FORGEJO_CONFIG_DIR="$c/forgejo-config" \
    "$@" bash "$SCRIPT" $args 2>&1)"
  rc=$?
  CASE="$c"
}
calls() { cat "$CASE/calls"; }
restic_calls() { grep '^repo=' "$CASE/calls" || true; }

# ── Locked vault: skip cleanly ───────────────────────────────────────────────
# After a reboot /mercurius is an empty directory on the plain disk. Nothing
# may be exported, dumped or uploaded, and the skip is not a failure.
run_case locked "backup mercurius" MOCK_MOUNT_SRC=""
assert_eq "$rc" "0" "a locked vault is not a failure"
assert_contains "$out" "vault is locked" "says why it skipped"
assert_eq "$(calls)" "" "a locked vault runs no docker, restic or ntfy"
assert_missing "$CASE/mercurius/backup/stage" "a locked vault stages nothing"
assert_missing "$CASE/state/last-success.mercurius" "a skip is not stamped as success"

# A different device on the mount point is not the vault either.
run_case wrongdev "backup mercurius" MOCK_MOUNT_SRC="/dev/sda1"
assert_eq "$rc" "0" "another device on /mercurius is skipped"
assert_eq "$(calls)" "" "another device on /mercurius is never backed up"

# ── Mercurius: export and dump staged inside the vault, plus the wiki ────────
run_case mercurius "backup mercurius" MOCK_MOUNT_SRC="$UNLOCKED"
assert_eq "$rc" "0" "mercurius backup succeeds"
assert_contains "$(calls)" "docker exec paperless document_exporter /usr/src/paperless/export" "runs document_exporter"
assert_contains "$(calls)" "docker exec mercurius-db sh -c" "dumps Postgres from mercurius-db"
assert_file "$CASE/mercurius/backup/stage/paperless.dump" "pgdump-bytes" "the dump is staged inside the vault"
assert_file "$CASE/mercurius/backup/stage/paperless-image.txt" "ghcr.io/paperless-ngx/paperless-ngx:3.3.4" "records the Paperless image that exported"
assert_eq "$(find "$CASE/state" -name '*.dump*' | wc -l)" "0" "no dump lands on the plain disk"
assert_contains "$(restic_calls)" "$CASE/mercurius/export $CASE/mercurius/backup/stage $CASE/mercurius/silverbullet" "snapshots the export, the staged dump and the wiki"
assert_contains "$(restic_calls)" "--tag mercurius" "tags the snapshot"
[[ -f "$CASE/state/last-success.mercurius" ]] && ok "stamps success" || bad "stamps success" "no last-success.mercurius"

# Only the vault repository and the vault's own password are used.
mismatch=""
while IFS= read -r line; do
  [[ "$line" == "repo=rclone:gdrive:the-loft/vault pass=$CASE/mercurius/backup/restic.pass rclone=$WORK/gdrive.conf ::"* ]] \
    || mismatch="$line"
done < <(restic_calls)
assert_eq "$mismatch" "" "mercurius uses only the vault repository and password"
assert_absent "$(restic_calls)" "the-loft/open" "mercurius never touches the open repository"

# Retention: the plan's 7/4/12, and the vault keeps every year.
assert_contains "$(restic_calls)" "forget --tag mercurius --group-by host,tags --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --keep-yearly unlimited" "vault retention keeps yearlies forever"
assert_absent "$(restic_calls)" "--prune" "nightly run does not prune"

# A failed export must not produce a snapshot of stale data.
run_case exportfail "backup mercurius" MOCK_MOUNT_SRC="$UNLOCKED" MOCK_DOCKER_FAIL_ON="document_exporter"
assert_fails "$rc" "a failed export fails the job"
assert_eq "$(restic_calls)" "" "a failed export uploads nothing"
assert_missing "$CASE/state/last-success.mercurius" "a failed export is not stamped as success"
assert_contains "$(calls)" "curl" "a failed export notifies"

run_case dumpfail "backup mercurius" MOCK_MOUNT_SRC="$UNLOCKED" MOCK_DOCKER_FAIL_ON="pg_dump"
assert_fails "$rc" "a failed pg_dump fails the job"
assert_eq "$(restic_calls)" "" "a failed pg_dump uploads nothing"
assert_missing "$CASE/mercurius/backup/stage/paperless.dump" "a failed pg_dump leaves no half-written dump"

# An empty wiki folder on an unlocked vault means the data is gone; backing it
# up would only push good snapshots out of retention.
EMPTY_WIKI=1 run_case wiki-empty "backup mercurius" MOCK_MOUNT_SRC="$UNLOCKED"
assert_fails "$rc" "an empty wiki folder fails"
assert_contains "$out" "silverbullet is missing or empty" "says so"
assert_eq "$(restic_calls)" "" "an empty wiki folder is not backed up"

# ── Forgejo ──────────────────────────────────────────────────────────────────
run_case forgejo "backup forgejo" MOCK_MOUNT_SRC=""
assert_eq "$rc" "0" "forgejo backup succeeds"
assert_contains "$(calls)" "docker exec forgejo forgejo dump --file - --type tar" "runs forgejo dump to stdout"
assert_contains "$(calls)" "docker exec kennl-db sh -c" "dumps Postgres from kennl-db"
assert_contains "$(restic_calls)" "repo=rclone:gdrive:the-loft/open pass=$CASE/etc/open.pass" "forgejo uses the open repository"
assert_contains "$(restic_calls)" "--tag forgejo $CASE/state/stage/forgejo" "snapshots the staged files"
assert_missing "$CASE/state/stage/forgejo" "staging is removed after a run"

# What the snapshot contains is checked by looking at the staged files at the
# moment restic runs.
mock restic 'echo "repo=$RESTIC_REPOSITORY pass=$RESTIC_PASSWORD_FILE rclone=$RCLONE_CONFIG :: $*" >> "$CALLS"
case "$*" in *"backup "*) ls "$BACKUP_STATE_DIR/stage/forgejo" | tr "\n" " " >> "$CALLS.staged" ;; esac
exit 0'
run_case forgejo-files "backup forgejo"
assert_eq "$(cat "$CASE/calls.staged")" "app.ini forgejo-db.dump forgejo-dump.tar " "stages the dump, the pg_dump and app.ini"

mock restic "$RESTIC_MOCK"

run_case forgejo-fail "backup forgejo" MOCK_DOCKER_FAIL_ON="forgejo dump"
assert_fails "$rc" "a failed forgejo dump fails the job"
assert_eq "$(restic_calls)" "" "a failed forgejo dump uploads nothing"
assert_missing "$CASE/state/stage/forgejo" "staging is removed after a failure"

# ── One failure does not stop the others ─────────────────────────────────────
run_case isolate "backup" MOCK_MOUNT_SRC="$UNLOCKED" MOCK_DOCKER_FAIL_ON="document_exporter"
assert_fails "$rc" "any failed job fails the run"
assert_contains "$(restic_calls)" "--tag forgejo" "forgejo still runs after mercurius fails"
assert_contains "$(calls)" "curl -fsS -m 20" "failure goes to ntfy"
assert_contains "$(calls)" "https://ntfy.test/loft-backup" "to the configured topic"
assert_contains "$(calls)" "Backup failed: mercurius" "naming the failed job"
assert_absent "$(calls)" "mercurius forgejo" "without blaming the job that worked"

run_case quiet "backup" MOCK_MOUNT_SRC="$UNLOCKED"
assert_eq "$rc" "0" "all jobs succeed"
assert_absent "$(calls)" "curl" "success sends no notification"

run_case nontfy "backup mercurius" MOCK_MOUNT_SRC="$UNLOCKED" MOCK_DOCKER_FAIL_ON="document_exporter" BACKUP_NTFY_URL=""
assert_fails "$rc" "failure still fails without an ntfy URL"
assert_absent "$(calls)" "curl" "no ntfy URL, no curl"

# ── Input checks ─────────────────────────────────────────────────────────────
run_case badjob "backup nonsense"
assert_fails "$rc" "an unknown job is rejected"
assert_contains "$out" "unknown job" "says so"

run_case noremote "backup" BACKUP_REMOTE=""
assert_fails "$rc" "refuses an unset remote"
assert_contains "$out" "BACKUP_REMOTE is unset" "says so"

run_case noconfig "backup" BACKUP_RCLONE_CONFIG="$WORK/absent.conf"
assert_fails "$rc" "refuses a missing rclone config"
assert_eq "$(calls)" "" "runs nothing without credentials"

run_case usage ""
assert_fails "$rc" "needs a subcommand"

# ── Weekly check ─────────────────────────────────────────────────────────────
run_check() { # case: fresh success stamps for every job; a case may then age one
  local c="$WORK/$1"
  mkdir -p "$c/state"
  local j
  for j in mercurius forgejo; do date -Is > "$c/state/last-success.$j"; done
}
run_check weekly
run_case weekly "check" MOCK_MOUNT_SRC="$UNLOCKED"
assert_eq "$rc" "0" "weekly check passes on fresh repositories"
for repo in vault open; do
  assert_contains "$(restic_calls)" "repo=rclone:gdrive:the-loft/${repo}" "checks ${repo}"
done
assert_contains "$(restic_calls)" "prune" "prunes weekly"
assert_contains "$(restic_calls)" "check --read-data-subset 5%" "reads a data subset"

run_check weekly-locked
run_case weekly-locked "check" MOCK_MOUNT_SRC=""
assert_eq "$rc" "0" "weekly check skips a locked vault"
assert_absent "$(restic_calls)" "the-loft/vault" "a locked vault is not opened by the check"
assert_contains "$(restic_calls)" "the-loft/open" "the open repository is still checked"

run_check weekly-fail
run_case weekly-fail "check" MOCK_MOUNT_SRC="$UNLOCKED" MOCK_RESTIC_FAIL_ON="check"
assert_fails "$rc" "a failed repository check fails"
assert_contains "$(calls)" "Repository check failed" "and notifies"

# A vault that has been locked for days leaves no recent snapshot; the skip is
# silent, so the weekly check must say so.
run_check weekly-stale
touch -d '10 days ago' "$WORK/weekly-stale/state/last-success.mercurius"
run_case weekly-stale "check" MOCK_MOUNT_SRC=""
assert_fails "$rc" "a stale job fails the weekly check"
assert_contains "$out" "mercurius: no successful backup in 3 days" "naming the job"
assert_contains "$(calls)" "No recent backup for: mercurius" "and notifies"

# ── Uptime Kuma push monitors (the Homepage Backups tile) ────────────────────
printf 'mercurius https://uptime.test/api/push/tok-merc\nforgejo https://uptime.test/api/push/tok-forgejo\ncheck https://uptime.test/api/push/tok-check\n' > "$WORK/push"
run_case push-ok "backup mercurius forgejo" MOCK_MOUNT_SRC="$UNLOCKED" BACKUP_NTFY_URL="" BACKUP_PUSH_FILE="$WORK/push"
assert_contains "$(calls)" "tok-merc?status=up&msg=OK" "a good job reports up"
assert_contains "$(calls)" "tok-forgejo?status=up&msg=OK" "each job uses its own monitor"

run_case push-fail "backup mercurius forgejo" MOCK_MOUNT_SRC="$UNLOCKED" MOCK_DOCKER_FAIL_ON="document_exporter" BACKUP_NTFY_URL="" BACKUP_PUSH_FILE="$WORK/push"
assert_contains "$(calls)" "tok-merc?status=down&msg=FAILED" "a failed job reports down"
assert_contains "$(calls)" "tok-forgejo?status=up" "a good job still reports up after another fails"

# A skip pushes nothing; the monitor lapses to down on its own.
run_case push-skip "backup mercurius" MOCK_MOUNT_SRC="" BACKUP_NTFY_URL="" BACKUP_PUSH_FILE="$WORK/push"
assert_absent "$(calls)" "curl" "a locked vault pushes nothing"

# A job with no monitor listed, or no file at all, is not an error.
printf 'check https://uptime.test/api/push/tok-check\n' > "$WORK/push-checkonly"
run_case push-none "backup forgejo" BACKUP_NTFY_URL="" BACKUP_PUSH_FILE="$WORK/push-checkonly"
assert_eq "$rc" "0" "a job without a monitor still succeeds"
run_case push-nofile "backup forgejo" BACKUP_NTFY_URL=""
assert_eq "$rc" "0" "no push file is fine"
assert_absent "$(calls)" "curl" "no push file, no curl"

run_check push-check
run_case push-check "check" MOCK_MOUNT_SRC="$UNLOCKED" BACKUP_NTFY_URL="" BACKUP_PUSH_FILE="$WORK/push"
assert_contains "$(calls)" "tok-check?status=up" "a good weekly check reports up"
run_check push-checkfail
run_case push-checkfail "check" MOCK_MOUNT_SRC="$UNLOCKED" MOCK_RESTIC_FAIL_ON="check" BACKUP_NTFY_URL="" BACKUP_PUSH_FILE="$WORK/push"
assert_contains "$(calls)" "tok-check?status=down" "a failed weekly check reports down"

# The Backups tile is commented out while backups are shelved.
homepage="$(grep -v '^ *#' "${ROOT}/services/houstn/homepage-config/services.yaml")"
assert_absent "$homepage" "BACKUP_KUMA_SLUG" "the Backups tile is off while shelved"
assert_contains "$(cat "${ROOT}/services/houstn/.env.example")" "HOMEPAGE_VAR_BACKUP_KUMA_SLUG=" "its slug is in .env.example"

# ── init ─────────────────────────────────────────────────────────────────────
run_case init-new "init" MOCK_MOUNT_SRC="$UNLOCKED" MOCK_RESTIC_HAS_REPO=1
assert_eq "$rc" "0" "init succeeds"
assert_contains "$(restic_calls)" "repo=rclone:gdrive:the-loft/vault pass=$CASE/mercurius/backup/restic.pass rclone=$WORK/gdrive.conf :: init" "initialises the vault repository"
assert_contains "$(restic_calls)" "repo=rclone:gdrive:the-loft/open pass=$CASE/etc/open.pass rclone=$WORK/gdrive.conf :: init" "initialises the open repository"

run_case init-again "init" MOCK_MOUNT_SRC="$UNLOCKED"
assert_eq "$rc" "0" "init is repeatable"
assert_absent "$(restic_calls)" ":: init" "an existing repository is left alone"

run_case init-locked "init" MOCK_MOUNT_SRC=""
assert_fails "$rc" "init needs the vault unlocked"
assert_contains "$out" "unlock the vault first" "says so"

# ── Manifests agree ──────────────────────────────────────────────────────────
conf="$(cat "${ROOT}/hosts/space-needle/host.conf")"
setup="$(cat "${ROOT}/setup.sh")"
script="$(cat "$SCRIPT")"
assert_contains "$conf" 'BACKUP_ENABLED="false"' "backups are shelved on space-needle (setup.sh installs nothing)"
assert_contains "$conf" "BACKUP_JOBS=(mercurius forgejo)" "the job list is kept for when it returns"
assert_contains "$setup" "loft-backup.timer" "setup.sh installs the nightly timer"
assert_contains "$setup" "loft-backup-check" "setup.sh installs the weekly check"
assert_contains "$setup" "Persistent=true" "a missed night runs at next boot"
assert_contains "$setup" "restic rclone" "setup.sh installs restic and rclone"
# The jobs back up folders the host provisions and containers Compose names.
assert_contains "$conf" "/opt/kennl/forgejo/config" "host.conf provisions Forgejo's config folder"
assert_contains "$script" "MERCURIUS_MOUNT:=/mercurius" "script default matches the vault mount"
assert_contains "$conf" '[mercurius]="/mercurius"' "which host.conf waits for"
assert_contains "$script" "FORGEJO_CONFIG_DIR:=/opt/kennl/forgejo/config" "script default matches Forgejo"
for name in paperless mercurius-db forgejo kennl-db; do
  grep -rq "container_name: ${name}$" "${ROOT}/services/mercurius" "${ROOT}/services/kennl" \
    && ok "Compose names container ${name}" || bad "Compose names container ${name}" "not found"
done
# The unit file template must not put the vault's password anywhere but the vault.
assert_absent "$setup" "restic.pass" "setup.sh never writes the vault password"

finish
