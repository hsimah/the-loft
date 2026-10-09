#!/usr/bin/env bash
# test-clog-deploy.sh — exercise clog-deploy.sh's ordering and failure recovery
# with mocked docker/curl and a file standing in for the SQLite database. The
# release is a real archive staged by the real stage-release.sh.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/tests/lib/assert.sh"
require jq flock

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
MOCK_BIN="$WORK/bin"
mkdir -p "$MOCK_BIN"

# ── Mocks ────────────────────────────────────────────────────────────────────
# The "database" is a text file: install creates it, user:add appends
# "user NAME ROLE PASSWORD", backup copies it, and the editor-count query
# counts editor lines. FAIL_AT makes one step fail.
mock docker 'args=("$@")
has() { local a; for a in "${args[@]}"; do [[ "$a" == "$1" ]] && return 0; done; return 1; }
db="$DATA/clog.sqlite"
[[ "$1" == info ]] && { echo "{\"MemoryLimit\":true}"; exit 0; }
if has pull && [[ "${FAIL_AT:-}" == pull ]]; then echo "pull failed" >&2; exit 1; fi
if has config && has json; then
  echo "{\"services\":{\"clog\":{\"image\":\"nginx:test\"},\"mushr\":{\"image\":\"caddy:test\"}}}"; exit 0
fi
has clog-cli || exit 0
for i in "${!args[@]}"; do [[ "${args[$i]}" == clog-cli ]] && break; done
cmd=("${args[@]:i+1}")
case "${cmd[0]:-}" in
  install) touch "$db"; [[ "${FAIL_AT:-}" != install ]] || { echo "schema failed" >&2; exit 1; } ;;
  user:add) echo "user ${cmd[1]} ${cmd[2]} $(cat)" >> "$db" ;;
  backup) [[ "${FAIL_AT:-}" != backup ]] || { echo "backup failed" >&2; exit 1; }
          cp "$db" "$DATA/${cmd[1]##*/}" ;;
  -r) [[ "${cmd[1]}" != *clog_users* ]] || grep -c "^user [^ ]* editor " "$db" ;;
esac
exit 0'
mock curl 'case "${@: -1}" in
  */healthz) [[ "${FAIL_AT:-}" == health ]] && echo "{\"ok\":false}" || echo "{\"ok\":true}" ;;
  *) echo OK ;;
esac'
mock hostname  'echo viking'
mock systemctl 'exit 0'
mock nft       'exit 0'
mock chown     'exit 0'

# ── Fixture repository and system root ───────────────────────────────────────
REPO="$WORK/repo"
SYS="$WORK/system"
DATA="$SYS/var/lib/clog/data"
STATE="$SYS/var/lib/loft/deploy"
RELEASES="$SYS/opt/clog/releases"
ENV_FILE="$REPO/services/clog/.env"
PENDING="$STATE/clog-pending.json"
RECORD="$STATE/clog.json"
mkdir -p "$REPO/control-plane" "$REPO/hosts/viking/overrides/mushr" "$REPO/services/clog" "$SYS/etc/loft"
touch "$SYS/etc/loft/dmz-ready"
cp "${ROOT}/hosts/viking/overrides/mushr/Caddyfile" \
   "${ROOT}/hosts/viking/overrides/mushr/docker-compose.override.yml" "$REPO/hosts/viking/overrides/mushr/"
cp "${ROOT}/services/clog/stage-release.sh" "$REPO/services/clog/"
sed -e "s#^SYSTEM=\"\"#SYSTEM=\"${SYS}\"#" -e 's/\[\[ \$EUID -eq 0 /[[ 0 -eq 0 /' \
  "${ROOT}/control-plane/clog-deploy.sh" > "$REPO/control-plane/clog-deploy.sh"

# A valid release archive, pinned by the fixture manifest.
make_archive() { # path [content]
  local src f
  src="$(mktemp -d "$WORK/src.XXXXXX")"
  for f in server/standalone/public/index.php server/standalone/cli.php server/vendor/autoload.php \
      client/dist/.vite/manifest.json client/dist/assets/stylex.css; do
    mkdir -p "$src/$(dirname "$f")"; printf '%s' "${2:-{\}}" > "$src/$f"
  done
  tar -C "$src" -czf "$1" server client
}
ARCHIVE="$WORK/clog.tar.gz"
make_archive "$ARCHIVE"
SHA="$(sha256sum "$ARCHIVE" | cut -d' ' -f1)"
TARGET="$RELEASES/$SHA"
jq --arg sha "$SHA" '.sha256 = $sha' "${ROOT}/hosts/viking/clog-release.json" > "$REPO/hosts/viking/clog-release.json"
make_archive "$WORK/tampered.tar.gz" tampered

reset() {
  rm -rf "$SYS/var" "$SYS/opt" "$ENV_FILE"
  unset FAIL_AT
}
# Run a deploy, feeding the first editor's password on stdin; sets out,
# status and calls (the traced commands).
deploy() { # [archive]
  out="$(PATH="$MOCK_BIN:$PATH" DATA="$DATA" FAIL_AT="${FAIL_AT:-}" \
    bash "$REPO/control-plane/clog-deploy.sh" --archive "${1:-$ARCHIVE}" \
    --user fixture-editor --password-stdin <<< 'disposable-password' 2>&1)"
  status=$?
  calls="$(grep '^+ ' <<< "$out")"
}
line_of() { grep -n -m1 -- "$1" <<< "$calls" | cut -d: -f1; } # first call matching
existing() { # an installed Clog with one inventory row
  reset
  deploy
  echo "item existing" >> "$DATA/clog.sqlite"
}

# ── fresh install, then a rerun keeps account, data and proxy ────────────────
existing
assert_eq "$status" 0 "fresh install succeeds"
assert_contains "$(cat "$DATA/clog.sqlite")" "user fixture-editor editor disposable-password" \
  "creates the first editor with the password from stdin"
assert_file "$ENV_FILE" "CLOG_RELEASE_DIR=$TARGET" "selects the staged release"
assert_eq "$(jq -r .directory "$RECORD")" "$TARGET" "records the deployed release"
assert_contains "$calls" "--force-recreate --wait --wait-timeout 120 mushr" "first run refreshes Caddy once"

deploy
assert_eq "$status" 0 "rerun succeeds"
assert_eq "$(grep -c '^user ' "$DATA/clog.sqlite")" 1 "rerun adds no account"
assert_contains "$(cat "$DATA/clog.sqlite")" "item existing" "rerun keeps existing data"
assert_absent "$calls" "user:add" "rerun does not run user:add"
stop="$(line_of ' stop clog clog-php')"
backup="$(line_of 'clog-cli backup')"
[[ -n "$stop" && -n "$backup" && "$stop" -lt "$backup" ]] && ok "writes stop before the backup" \
  || bad "writes stop before the backup" "stop line '${stop}', backup line '${backup}'"
backup_file="$(sed -n 's/^Local backup: \(.*\)\. Copy it.*/\1/p' <<< "$out")"
[[ -n "$backup_file" && -f "$backup_file" ]] && ok "backup file exists" || bad "backup file exists" "'${backup_file}'"
assert_absent "$(grep ' up .* mushr$' <<< "$calls")" "--force-recreate" "unchanged Caddy is not recreated"
assert_missing "$PENDING" "success clears the pending record"
assert_eq "$(stat -c %a "$ENV_FILE")" 600 ".env stays private"

# ── checksum or pull failure leaves the running deployment untouched ─────────
existing
before="$(cat "$ENV_FILE")"
deploy "$WORK/tampered.tar.gz"
assert_fails "$status" "checksum mismatch fails"
assert_absent "$calls" " stop " "checksum mismatch stops nothing"
assert_missing "$PENDING" "checksum mismatch writes no pending record"
assert_file "$ENV_FILE" "$before" "checksum mismatch leaves .env"
FAIL_AT=pull deploy
assert_fails "$status" "image pull failure fails"
assert_absent "$calls" " stop " "pull failure stops nothing"
assert_missing "$PENDING" "pull failure writes no pending record"
assert_file "$ENV_FILE" "$before" "pull failure leaves .env"

# ── backup failure prevents the schema change ────────────────────────────────
existing
FAIL_AT=backup deploy
assert_fails "$status" "backup failure fails"
assert_absent "$calls" "clog-cli install" "backup failure prevents install"
[[ -f "$PENDING" ]] && ok "backup failure leaves the pending record" || bad "backup failure leaves the pending record" "missing"

# ── migration failure keeps the backup and blocks an unsafe retry ────────────
existing
record="$(cat "$RECORD")"
FAIL_AT=install deploy
assert_fails "$status" "install failure fails"
assert_eq "$(jq -r .phase "$PENDING")" installing "pending record says installing"
backup_file="$(jq -r .backup "$PENDING")"
[[ -f "$backup_file" ]] && ok "install failure keeps the backup" || bad "install failure keeps the backup" "'${backup_file}'"
assert_file "$RECORD" "$record" "install failure leaves the success record"
assert_absent "$calls" "clog-php clog" "install failure never starts Clog"
deploy
assert_fails "$status" "retry after an unfinished deployment fails"
assert_contains "$out" "Unfinished deployment" "explains the unfinished deployment"
assert_absent "$calls" "stage-release.sh" "unfinished deployment stages nothing"

# ── failed health stops the app without a success record ─────────────────────
reset
FAIL_AT=health deploy
assert_fails "$status" "failed health check fails"
[[ -f "$PENDING" ]] && ok "failed health leaves the pending record" || bad "failed health leaves the pending record" "missing"
assert_missing "$RECORD" "failed health writes no success record"
assert_contains "$(tail -1 <<< "$calls")" " stop clog clog-php" "failed health ends by stopping Clog"

# ── concurrent apply ─────────────────────────────────────────────────────────
reset
mkdir -p "$STATE"
flock "$STATE/clog.lock" sleep 10 &
HOLDER=$!
until ! flock -n "$STATE/clog.lock" true; do :; done
deploy
kill "$HOLDER" 2> /dev/null; wait "$HOLDER" 2> /dev/null
assert_fails "$status" "concurrent apply fails"
assert_contains "$out" "Another Clog" "explains the lock"
assert_absent "$calls" "stage-release.sh" "concurrent apply stages nothing"

# ── release selection ────────────────────────────────────────────────────────
reset
echo "CLOG_RELEASE_DIR=$RELEASES/pending" > "$ENV_FILE"
deploy
assert_eq "$status" 0 "fresh install accepts the example .env placeholder"
assert_file "$ENV_FILE" "CLOG_RELEASE_DIR=$TARGET" "placeholder is replaced by the staged release"

reset
mkdir -p "$DATA"
touch "$DATA/clog.sqlite"
deploy
assert_fails "$status" "existing database without a selected release fails"
assert_contains "$out" "no selected release" "explains the missing release"
assert_absent "$calls" "stage-release.sh" "missing release stages nothing"

# ── first account needs credentials ──────────────────────────────────────────
reset
out="$(PATH="$MOCK_BIN:$PATH" DATA="$DATA" bash "$REPO/control-plane/clog-deploy.sh" \
  --archive "$ARCHIVE" < /dev/null 2>&1)"
assert_fails "$?" "non-interactive fresh install without --password-stdin fails"
assert_contains "$out" "run interactively" "explains how to create the first account"
out="$(PATH="$MOCK_BIN:$PATH" DATA="$DATA" bash "$REPO/control-plane/clog-deploy.sh" \
  --archive "$ARCHIVE" --user fixture-editor --password-stdin <<< 'short' 2>&1)"
assert_fails "$?" "short password is rejected"
assert_absent "$out" "stage-release.sh" "bad credentials fail before staging"

# ── plan and manifest ────────────────────────────────────────────────────────
PLAN_BIN="$WORK/plan-bin"
mkdir -p "$PLAN_BIN"
for c in docker curl systemctl nft sudo; do printf '#!/bin/sh\nexit 97\n' > "$PLAN_BIN/$c"; chmod +x "$PLAN_BIN/$c"; done
out="$(PATH="$PLAN_BIN:$PATH" bash "${ROOT}/control-plane/clog-deploy.sh" --plan 2>&1)"
assert_eq "$?" 0 "plan succeeds without host tools"
assert_contains "$out" "SHA-256: $(jq -r .sha256 "${ROOT}/hosts/viking/clog-release.json")" "plan shows the pinned checksum"

jq '.url = "http://example.com/unpinned.tar.gz"' "${ROOT}/hosts/viking/clog-release.json" \
  > "$REPO/hosts/viking/clog-release.json"
out="$(bash "$REPO/control-plane/clog-deploy.sh" --plan 2>&1)"
assert_fails "$?" "unpinned manifest URL is rejected"
assert_contains "$out" "Invalid pinned Clog release manifest" "explains the manifest error"

# ── entry points ─────────────────────────────────────────────────────────────
LC="$WORK/loft-ctl-root"
mkdir -p "$LC/hosts/viking" "$LC/control-plane" "$LC/bin"
cp "${ROOT}/loft-ctl" "$LC/"
cp "${ROOT}/control-plane/common.sh" "$LC/control-plane/"
echo 'SERVICES=(mushr pawst clog)' > "$LC/hosts/viking/host.conf"
printf '#!/bin/sh\necho viking\n' > "$LC/bin/hostname"
printf '#!/bin/sh\nprintf "%%s\\n" "$@"\n' > "$LC/bin/bash"
printf '#!/bin/sh\nexit 97\n' > "$LC/bin/sudo"
chmod +x "$LC/bin/"*
out="$(PATH="$LC/bin:$PATH" "$BASH" "$LC/loft-ctl" deploy clog --plan 2>&1)"
assert_eq "$?" 0 "loft-ctl routes --plan without sudo"
assert_contains "$out" "control-plane/clog-deploy.sh"$'\n'"--plan" "loft-ctl runs clog-deploy.sh --plan"

SETUP="$WORK/setup-root"
mkdir -p "$SETUP/control-plane"
echo 'compose_args_for() { echo "-f $1"; }' > "$SETUP/control-plane/common.sh"
section="$(sed -n '/^# ─── 11\. Deploy services/,/^# ─── 11a\./{//!p}' "${ROOT}/setup.sh")"
out="$(REPO_DIR="$SETUP" bash -c 'set -euo pipefail
info() { echo "$*"; }
warn() { echo "$*"; }
docker() { echo "docker $*"; }
SERVICES=(clog pawst)
'"$section" 2>&1)"
assert_eq "$?" 0 "setup's deploy section runs"
assert_contains "$out" "loft-ctl deploy clog" "setup points Clog at loft-ctl deploy"
docker_calls="$(grep '^docker ' <<< "$out")"
[[ -n "$docker_calls" ]] && ok "setup still deploys other services" || bad "setup still deploys other services" "no docker calls"
assert_absent "$docker_calls" "clog" "setup never runs Compose for Clog"

finish
