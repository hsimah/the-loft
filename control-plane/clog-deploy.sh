#!/usr/bin/env bash
# clog-deploy.sh — deploy the pinned standalone Clog release on Viking. No Git,
# DNS or boot edits. Run through `loft-ctl deploy clog`; phases, state files and
# recovery are in docs/services/clog.md.
set -euo pipefail
shopt -s inherit_errexit

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Prefix for every host path; tests point it at a temp dir.
SYSTEM=""
RELEASES="${SYSTEM}/opt/clog/releases"
DATA="${SYSTEM}/var/lib/clog/data"
RUNTIME="${SYSTEM}/var/lib/clog/runtime"
STATE="${SYSTEM}/var/lib/loft/deploy"
DMZ_READY="${SYSTEM}/etc/loft/dmz-ready"
MANIFEST="${REPO_DIR}/hosts/viking/clog-release.json"
ENV_FILE="${REPO_DIR}/services/clog/.env"
CADDYFILE="${REPO_DIR}/hosts/viking/overrides/mushr/Caddyfile"
PENDING="${STATE}/clog-pending.json"
RECORD="${STATE}/clog.json"
SHA_RE='^[a-f0-9]{64}$'
SANDBOX=(--rm --network none --read-only --user 1003:1003 --cap-drop ALL
  --security-opt no-new-privileges --tmpfs /tmp:uid=1003,gid=1003,mode=1770)

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: clog-deploy.sh [--plan] [--archive PATH] [--user NAME] [--password-stdin]

Deploy the pinned standalone Clog release on Viking.
  --plan            print the deployment plan without host changes
  --archive PATH    use a local archive instead of downloading; checksum still required
  --user NAME       first editor username; ignored when an editor already exists
  --password-stdin  read the first editor's password from stdin (needs --user)
EOF
}

PLAN=false
ARCHIVE=""
USERNAME=""
PASSWORD=""
PASSWORD_STDIN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) PLAN=true; shift ;;
    --archive) [[ $# -ge 2 ]] || die "--archive needs a path"; ARCHIVE="$2"; shift 2 ;;
    --user) [[ $# -ge 2 ]] || die "--user needs a name"; USERNAME="$2"; shift 2 ;;
    --password-stdin) PASSWORD_STDIN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown option: $1" ;;
  esac
done

# ── Pinned release ───────────────────────────────────────────────────────────
jq -e '
  type == "object" and keys == ["sha256", "url", "version"] and all(.[]; type == "string")
  and (.version | test("\\A[A-Za-z0-9][A-Za-z0-9._-]*\\z"))
  and (.sha256 | test("\\A[a-f0-9]{64}\\z"))
  and .url == "https://github.com/hsimah/clog/releases/download/\(.version)/clog-standalone.tar.gz"
' "$MANIFEST" > /dev/null 2>&1 || die "Invalid pinned Clog release manifest"
VERSION="$(jq -r .version "$MANIFEST")"
URL="$(jq -r .url "$MANIFEST")"
SHA256="$(jq -r .sha256 "$MANIFEST")"
TARGET="${RELEASES}/${SHA256}"

if $PLAN; then
  echo "Deploy Clog ${VERSION} to Viking from ${URL}"
  echo "SHA-256: ${SHA256}"
  echo "Verify/stage release and images; validate configs; prepare private storage and Caddy."
  echo "Stop Clog writes; back up existing SQLite; install schema; create an editor only if needed."
  echo "Select release; recreate Clog; check origin and existing sites; record successful deployment."
  echo "No Git pull, Cloudflare changes, boot edits, reboot or automatic database rollback."
  exit 0
fi

# ── Helpers ──────────────────────────────────────────────────────────────────
# Trace and run a command with Compose profiles cleared; the lock fd stays here.
run() { # [--release DIR] command...
  local release=() status=0
  if [[ "$1" == --release ]]; then release=("CLOG_RELEASE_DIR=$2"); shift 2; fi
  echo "+ $*" >&2
  env COMPOSE_PROFILES= "${release[@]}" "$@" 9>&- || status=$?
  [[ $status -eq 0 ]] || echo "ERROR: command failed (exit ${status}): $*" >&2
  return "$status"
}

compose() { # [--release DIR] service args...
  local release=() service files override
  if [[ "$1" == --release ]]; then release=(--release "$2"); shift 2; fi
  service="$1"; shift
  files=(-f "${REPO_DIR}/services/${service}/docker-compose.yml")
  override="${REPO_DIR}/hosts/viking/overrides/${service}/docker-compose.override.yml"
  if [[ -f "$override" ]]; then files+=(-f "$override"); fi
  run "${release[@]}" docker compose --project-directory "${REPO_DIR}/services/${service}" "${files[@]}" "$@"
}

cli() { # release args...
  compose --release "$1" clog run --rm --no-deps -T clog-cli "${@:2}"
}

probe() { # host path
  run curl --noproxy '*' --fail-with-body --silent --show-error --max-time 10 \
    -H "Host: $1" "http://127.0.0.1:8080$2"
}

# Write via a same-directory temp file so readers never see a partial file.
atomic_write() { # path content [mode]
  local tmp
  tmp="$(mktemp "$(dirname "$1")/.clog-XXXXXX")"
  if printf '%s\n' "$2" > "$tmp" && sync "$tmp" && chmod "${3:-600}" "$tmp" && mv -f "$tmp" "$1"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

null_if_empty() { # value; prints a JSON string or null
  if [[ -n "$1" ]]; then jq -n --arg v "$1" '$v'; else echo null; fi
}

# ── Phases ───────────────────────────────────────────────────────────────────
preflight() {
  [[ $EUID -eq 0 && "$(hostname)" == viking ]] || die "Apply requires sudo on Viking; use --plan elsewhere"
  [[ -f "$DMZ_READY" ]] || die "Complete the Viking DMZ preparation first"
  local c info
  for c in docker curl systemctl nft; do
    command -v "$c" > /dev/null || die "Missing command: $c"
  done
  run systemctl is-active --quiet loft-firewall.service
  for c in loft_host loft_docker; do
    run nft list table inet "$c" > /dev/null
  done
  info="$(run docker info --format '{{json .}}')"
  if ! jq -e '.MemoryLimit' <<< "$info" > /dev/null; then
    echo "WARNING: Docker memory limits are not enforced. Boot settings are unchanged."
  fi
}

current_release() { # prints the selected release directory, or nothing
  [[ -f "$ENV_FILE" ]] || return 0
  local values current
  mapfile -t values < <(sed -n 's/^CLOG_RELEASE_DIR=\(..*\)$/\1/p' "$ENV_FILE")
  [[ ${#values[@]} -eq 1 ]] || die "Expected one CLOG_RELEASE_DIR in services/clog/.env"
  current="$(sed -E "s/^[[:space:]]+|[[:space:]]+\$//g; s/^[\"']+|[\"']+\$//g" <<< "${values[0]}")"
  if [[ "$current" == "${RELEASES}/pending" && ! -e "${DATA}/clog.sqlite" ]]; then
    return 0
  fi
  [[ "$(dirname "$current")" == "$RELEASES" && "$(basename "$current")" =~ $SHA_RE \
    && ! -L "$current" && -d "$current" ]] \
    || die "Current release must be an existing checksum-named release directory"
  echo "$current"
}

# Read-only query through the release's own PHP, so the host needs no sqlite3.
editor_count() { # release
  if [[ ! -f "${DATA}/clog.sqlite" ]]; then echo 0; return; fi
  local count
  count="$(compose --release "$1" clog run --rm --no-deps -T --entrypoint php clog-cli -r \
    '$db = new PDO("sqlite:/var/lib/clog/clog.sqlite", null, null, [PDO::SQLITE_ATTR_OPEN_FLAGS => PDO::SQLITE_OPEN_READONLY]); echo $db->query("SELECT COUNT(*) FROM clog_users WHERE enabled = 1 AND role = '\''editor'\''")->fetchColumn();')"
  [[ "$count" =~ ^[0-9]+$ ]] || die "Could not count editor accounts (got: ${count})"
  echo "$count"
}

password_bytes() { printf '%s' "$PASSWORD" | wc -c; }

# Collect the first account up front, before anything stops.
credentials() { # current-release
  local count confirm bytes
  count="$(editor_count "$1")"
  [[ "$count" -eq 0 ]] || return 0
  if $PASSWORD_STDIN; then
    [[ -n "$USERNAME" ]] || die "--password-stdin needs --user"
    IFS= read -r PASSWORD || [[ -n "$PASSWORD" ]] || die "No password on stdin"
  else
    [[ -t 0 ]] || die "No editor account: run interactively to create the first account"
    if [[ -z "$USERNAME" ]]; then
      read -rp 'First Clog username: ' USERNAME
      USERNAME="$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<< "$USERNAME")"
    fi
  fi
  [[ "$USERNAME" =~ ^[a-zA-Z0-9_.@-]{1,100}$ ]] || die "Invalid account name"
  if $PASSWORD_STDIN; then
    bytes="$(password_bytes)"
    (( bytes >= 12 && bytes <= 72 )) || die "Use a password between 12 and 72 bytes"
    return 0
  fi
  while true; do
    read -rsp 'Password (12–72 bytes): ' PASSWORD; echo >&2
    bytes="$(password_bytes)"
    if (( bytes < 12 || bytes > 72 )); then
      echo 'Use a password between 12 and 72 bytes.'
      continue
    fi
    read -rsp 'Confirm password: ' confirm; echo >&2
    [[ "$PASSWORD" == "$confirm" ]] && return 0
    echo 'Passwords did not match; try again.'
  done
}

DOWNLOAD_DIR=""
stage() {
  local archive="$ARCHIVE"
  if [[ -z "$archive" ]]; then
    DOWNLOAD_DIR="$(mktemp -d -t clog-download-XXXXXX)"
    archive="${DOWNLOAD_DIR}/clog.tar.gz"
    run curl --fail --location --proto =https --proto-redir =https \
      --connect-timeout 20 --max-time 300 --output "$archive" "$URL"
  fi
  run bash "${REPO_DIR}/services/clog/stage-release.sh" "$archive" "$SHA256" \
    --releases "$RELEASES" --reuse > /dev/null
}

prepare_storage() {
  local d
  for d in "$DATA" "${DATA}/sessions" "$RUNTIME"; do
    [[ ! -L "$d" ]] || die "Refusing a symlink for writable storage: $d"
    mkdir -p "$d"
    chown 1003:1003 "$d"
    chmod 0700 "$d"
  done
}

image_of() { # compose-service image-service
  compose --release "$TARGET" "$1" config --format json | jq -r --arg s "$2" '.services[$s].image'
}

validate() {
  compose --release "$TARGET" clog --profile tools config --quiet
  compose --release "$TARGET" clog --profile tools pull
  compose mushr config --quiet
  compose mushr pull mushr
  compose --release "$TARGET" clog run --rm --no-deps --entrypoint php clog-cli -r \
    'foreach (["pdo_sqlite","mbstring","Zend OPcache"] as $e) { if (!extension_loaded($e)) exit(1); } require "/opt/clog/server/standalone/bootstrap.php";'
  compose --release "$TARGET" clog run --rm --no-deps --entrypoint php-fpm clog-cli \
    --test --fpm-config /usr/local/etc/clog-fpm.conf
  # Validate without Compose run: a live Caddy owns the fixed network address.
  local image
  image="$(image_of clog clog)"
  run docker run "${SANDBOX[@]}" -v "${REPO_DIR}/services/clog/nginx.conf:/etc/nginx/nginx.conf:ro" \
    -v "${REPO_DIR}/services/clog/fastcgi.conf:/etc/nginx/clog-fastcgi.conf:ro" \
    --entrypoint nginx "$image" -t
  image="$(image_of mushr mushr)"
  run docker run "${SANDBOX[@]}" -v "${CADDYFILE}:/etc/caddy/Caddyfile:ro" \
    --cap-add NET_BIND_SERVICE -e XDG_DATA_HOME=/tmp/data -e XDG_CONFIG_HOME=/tmp/config \
    --entrypoint caddy "$image" validate --config /etc/caddy/Caddyfile
}

PROXY_DIGEST=""
prepare_proxy() {
  local cfg previous="" recreate=()
  cfg="$(compose mushr config --format json)"
  PROXY_DIGEST="$({ cat "$CADDYFILE"; jq -cS . <<< "$cfg"; } | sha256sum | cut -d' ' -f1)"
  if [[ -f "$RECORD" ]]; then previous="$(jq -r '.proxy_sha256 // empty' "$RECORD")"; fi
  # Unknown state gets one controlled refresh. Subsequent runs preserve unchanged ingress.
  [[ "$previous" == "$PROXY_DIGEST" ]] || recreate=(--force-recreate)
  compose mushr up -d --no-deps "${recreate[@]}" --wait --wait-timeout 120 mushr
  probe hsimah.com / > /dev/null
  probe hbla.ke / > /dev/null
}

BACKUP=""
write_pending() { # phase previous-directory
  atomic_write "$PENDING" "$(jq --arg phase "$1" --argjson prev "$(null_if_empty "$2")" \
    --argjson backup "$(null_if_empty "$BACKUP")" \
    '{phase: $phase, release: ., previous_directory: $prev, backup: $backup}' "$MANIFEST")"
}

ensure_account() {
  local count
  count="$(editor_count "$TARGET")"
  if [[ "$count" -gt 0 ]]; then
    echo 'Existing editor account retained.'
  elif [[ -n "$PASSWORD" ]]; then
    printf '%s' "$PASSWORD" | cli "$TARGET" user:add "$USERNAME" editor
  else
    die 'No enabled editor after installation'
  fi
}

select_release() {
  local owner content
  if [[ -f "$ENV_FILE" ]]; then owner="$(stat -c %u:%g "$ENV_FILE")"
  else owner="$(stat -c %u:%g "${REPO_DIR}/services/clog")"; fi
  content="$({ grep -v '^CLOG_RELEASE_DIR=' "$ENV_FILE" 2> /dev/null || true; echo "CLOG_RELEASE_DIR=${TARGET}"; })"
  atomic_write "$ENV_FILE" "$content"
  # Preserve ownership so the normal adminhabl loft-ctl can read it.
  chown "$owner" "$ENV_FILE"
}

# ── Deploy ───────────────────────────────────────────────────────────────────
CRITICAL=false
on_exit() {
  local status=$?
  if [[ -n "$DOWNLOAD_DIR" ]]; then rm -rf "$DOWNLOAD_DIR"; fi
  if [[ $status -ne 0 ]] && $CRITICAL; then
    # A possibly migrated database must not be served by the old release.
    compose --release "$TARGET" clog stop clog clog-php || true
    echo "Deployment incomplete. Clog was stopped; inspect ${PENDING}." >&2
  fi
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

preflight
mkdir -p "$STATE"
exec 9>> "${STATE}/clog.lock"
flock -n 9 || die "Another Clog deployment is running"
[[ ! -e "$PENDING" ]] || die "Unfinished deployment: inspect ${PENDING} and the recovery runbook first"
CURRENT="$(current_release)"
if [[ -f "${DATA}/clog.sqlite" && -z "$CURRENT" ]]; then
  die "Existing database has no selected release; restore services/clog/.env first"
fi
credentials "$CURRENT"
stage
prepare_storage
validate
prepare_proxy

# Mark the operation before stopping writes, so interruptions are visible.
write_pending stopping "$CURRENT"
CRITICAL=true
compose --release "${CURRENT:-$TARGET}" clog stop clog clog-php
if [[ -f "${DATA}/clog.sqlite" ]]; then
  BACKUP="${DATA}/pre-deploy-$(date -u +%Y%m%dT%H%M%S%6NZ).sqlite"
  cli "$CURRENT" backup "/var/lib/clog/${BACKUP##*/}"
  [[ -f "$BACKUP" ]] || die "Backup command did not create its output file"
  write_pending backed-up "$CURRENT"
fi
write_pending installing "$CURRENT"
cli "$TARGET" install
ensure_account
PASSWORD=""
select_release
compose --release "$TARGET" clog up -d --force-recreate --wait --wait-timeout 180 clog-php clog
health="$(probe clog.hsimah.com /healthz)"
jq -e '. == {"ok": true}' <<< "$health" > /dev/null 2>&1 || die "Unexpected Clog health response"
probe clog.hsimah.com /auth/login > /dev/null
probe hsimah.com / > /dev/null
probe hbla.ke / > /dev/null
atomic_write "$RECORD" "$(jq --arg dir "$TARGET" --arg proxy "$PROXY_DIGEST" \
  --argjson backup "$(null_if_empty "$BACKUP")" --arg at "$(date -u +%Y-%m-%dT%H:%M:%S.%6N+00:00)" \
  '. + {directory: $dir, proxy_sha256: $proxy, backup: $backup, deployed_at: $at}' "$MANIFEST")"
rm -f "$PENDING"
CRITICAL=false

echo 'Clog is healthy through Caddy: https://clog.hsimah.com'
echo 'For a first public cutover: viking-prod → clog.hsimah.com → HTTP mushr:8080;'
echo 'HTTP Host Header: clog.hsimah.com. Existing routes need no Cloudflare change.'
if [[ -n "$BACKUP" ]]; then
  echo "Local backup: ${BACKUP}. Copy it to encrypted off-host storage."
fi
