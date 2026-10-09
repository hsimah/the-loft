#!/usr/bin/env bash
# clog-runtime.sh — exercise a supplied standalone archive on the real
# non-root Nginx/FPM configs. Local only: disposable rootless Podman containers
# and a loopback test port. Not run by tests/run.sh (needs an archive).
#
# Usage: bash tests/clog-runtime.sh /path/to/clog-standalone.tar.gz
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/tests/lib/assert.sh"
require podman curl jq

PHP_IMAGE=docker.io/library/php:8.4.24-fpm-alpine
NGINX_IMAGE=docker.io/library/nginx:1.30.4-alpine
PASSWORD=disposable-test-password-2026

[[ $# -eq 1 && -f "$1" ]] || { echo "Usage: $0 /path/to/clog-standalone.tar.gz" >&2; exit 2; }
ARCHIVE="$(realpath "$1")"

ID="loft-clog-test-$(head -c 5 /dev/urandom | od -An -tx1 | tr -d ' \n')"
PHP_NAME="${ID}-php"
NGINX_NAME="${ID}-nginx"
WORK="$(mktemp -d -t loft-clog-test-XXXXXX)"
cleanup() {
  local name
  for name in "$NGINX_NAME" "$PHP_NAME"; do
    if [[ "$FAIL" -gt 0 ]]; then
      echo "── last log lines from ${name}" >&2
      podman logs --tail 5 "$name" >&2 2> /dev/null || true
    fi
    podman rm -f "$name" > /dev/null 2>&1 || true
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

die() { echo "ERROR: $*" >&2; exit 1; }

# ── Release, config and storage ──────────────────────────────────────────────
RELEASE="$(bash "${ROOT}/services/clog/stage-release.sh" "$ARCHIVE" \
  "$(sha256sum "$ARCHIVE" | cut -d' ' -f1)" --releases "$WORK/releases")" || die "Staging failed"
CONFIG="$WORK/config"
cp -r "${ROOT}/services/clog" "$CONFIG"
mkdir -m 700 "$WORK/data" "$WORK/data/sessions" "$WORK/runtime"

COMMON=(--userns=keep-id:uid=1003,gid=1003 --user 1003:1003 --read-only --cap-drop=ALL
  --security-opt=no-new-privileges --tmpfs=/tmp:mode=1777 --pids-limit=32)
PHP=("${COMMON[@]}" --network=none --memory=256m
  -e CLOG_DB=/var/lib/clog/clog.sqlite -e CLOG_SESSION_PATH=/var/lib/clog/sessions
  -e CLOG_ORIGIN=https://clog.hsimah.com
  -v "${RELEASE}:/opt/clog:ro,z" -v "${WORK}/data:/var/lib/clog:z" -v "${WORK}/runtime:/run/clog:z"
  -v "${CONFIG}/php-fpm.conf:/usr/local/etc/clog-fpm.conf:ro,z"
  -v "${CONFIG}/php.ini:/usr/local/etc/php/conf.d/zz-clog.ini:ro,z"
  -v "${CONFIG}/health.php:/usr/local/lib/clog-health.php:ro,z")
CLI=(php /opt/clog/server/standalone/cli.php)

podman run --rm "${PHP[@]}" "$PHP_IMAGE" "${CLI[@]}" install > /dev/null || die "install failed"
printf '%s' "$PASSWORD" | podman run --rm -i "${PHP[@]}" "$PHP_IMAGE" "${CLI[@]}" user:add runtime-test editor > /dev/null \
  || die "user:add failed"
podman run -d --name "$PHP_NAME" "${PHP[@]}" "$PHP_IMAGE" php-fpm --nodaemonize \
  --fpm-config /usr/local/etc/clog-fpm.conf > /dev/null || die "php-fpm did not start"
podman run -d --name "$NGINX_NAME" "${COMMON[@]}" --memory=48m -p 127.0.0.1::8080 \
  -v "${CONFIG}/nginx.conf:/etc/nginx/nginx.conf:ro,z" \
  -v "${CONFIG}/fastcgi.conf:/etc/nginx/clog-fastcgi.conf:ro,z" \
  -v "${RELEASE}/client/dist/assets:/srv/assets:ro,z" \
  -v "${WORK}/runtime:/run/clog:ro,z" \
  --entrypoint nginx "$NGINX_IMAGE" -g 'daemon off;' > /dev/null || die "nginx did not start"
PORT="$(podman port "$NGINX_NAME" 8080/tcp)"
PORT="${PORT##*:}"

# ── HTTP helper ──────────────────────────────────────────────────────────────
# One session cookie, replaced by any Set-Cookie, sent by hand: curl's cookie
# engine would withhold the Secure cookie over plain HTTP.
COOKIE=""
HOST=clog.hsimah.com
request() { # method path [body] [header...]; sets STATUS, HEADERS and BODY
  local method="$1" path="$2" body="${3-}" args=() set_cookie
  shift 2; [[ $# -gt 0 ]] && shift
  args=(--silent --max-time 10 --request "$method" -o "$WORK/body" -D "$WORK/headers"
    -w '%{http_code}' -H "Host: ${HOST}" -H "Cookie: ${COOKIE}")
  if [[ "$method" == POST ]]; then
    printf '%s' "$body" > "$WORK/request"
    args+=(--data-binary "@$WORK/request")
    [[ " $* " == *"Content-Type:"* ]] || args+=(-H 'Content-Type:')
  fi
  local h; for h in "$@"; do args+=(-H "$h"); done
  STATUS="$(curl "${args[@]}" "http://127.0.0.1:${PORT}${path}")" || STATUS=000
  HEADERS="$(tr -d '\r' < "$WORK/headers" 2> /dev/null)"
  BODY="$(tr -d '\0' < "$WORK/body" 2> /dev/null)"
  set_cookie="$(sed -n 's/^[Ss]et-[Cc]ookie: *\([^;]*\).*/\1/p' <<< "$HEADERS" | head -1)"
  [[ -z "$set_cookie" ]] || COOKIE="$set_cookie"
}
header() { sed -n "s/^$1: *//Ip" <<< "$HEADERS" | head -1; } # name

for _ in $(seq 30); do
  request GET /healthz
  [[ "$STATUS" == 200 ]] && break
  sleep 0.2
done
assert_eq "$STATUS" 200 "app becomes ready"
podman exec "$PHP_NAME" php /usr/local/lib/clog-health.php > /dev/null
assert_eq "$?" 0 "FPM health script passes"

# ── Routing and denied paths ─────────────────────────────────────────────────
HOST=unknown.invalid request GET /healthz
assert_eq "$STATUS" 404 "unknown Host is refused"
for path in /.env /server/vendor/autoload.php /clog.sqlite /assets/evil.php /assets/missing.js; do
  request GET "$path"
  assert_eq "$STATUS" 404 "${path} is not served"
done
request POST /graphql '{}' 'Content-Type: application/json'
assert_eq "$STATUS" 401 "GraphQL needs a session"

# ── Login, CSRF and session ──────────────────────────────────────────────────
request GET /auth/login
assert_eq "$STATUS" 200 "login page loads"
assert_contains "$(header Cache-Control)" no-store "login page is not cached"
csrf="$(grep -o 'name="csrf" value="[^"]*"' <<< "$BODY" | sed 's/.*value="//; s/"$//')"
form="$(jq -rn --arg c "$csrf" --arg p "$PASSWORD" '"username=runtime-test&password=\($p | @uri)&csrf=\($c | @uri)"')"
request POST /auth/login "$form" 'Content-Type: application/x-www-form-urlencoded'
assert_eq "$STATUS" 303 "login redirects"
cookie_flags="$(header Set-Cookie | tr '[:upper:]' '[:lower:]')"
assert_contains "$cookie_flags" secure "session cookie is Secure"
assert_contains "$cookie_flags" httponly "session cookie is HttpOnly"
request GET /auth/session
session="$BODY"
assert_eq "$(jq -r '.canWrite == true and .userId != "0"' <<< "$session" 2> /dev/null)" true "session can write"
nonce="$(jq -r .nonce <<< "$session" 2> /dev/null)"

request POST /graphql '{"query":"{ __typename }"}' 'Content-Type: application/json'
assert_eq "$STATUS" 403 "GraphQL without the CSRF header is refused"
request POST /graphql '{"query":"{ __typename }"}' 'Content-Type: application/json' "X-Clog-CSRF: ${nonce}"
assert_eq "$STATUS" 200 "GraphQL with the CSRF header succeeds"
assert_eq "$(jq -r 'has("data")' <<< "$BODY" 2> /dev/null)" true "GraphQL returns data"

# ── Deep links and assets ────────────────────────────────────────────────────
request GET /items
assert_eq "$STATUS" 200 "deep link serves the app"
assert_contains "$BODY" 'type="module"' "deep link loads the module bundle"
mapfile -t assets < <(grep -oE '(src|href)="/assets/[^"?]+' <<< "$BODY" | sed 's/.*="//')
for asset in "${assets[@]}"; do
  request GET "$asset"
  assert_eq "$STATUS" 200 "${asset} is served"
done

# ── Limits, logout and throttling ────────────────────────────────────────────
request POST /graphql "$(head -c 65537 /dev/zero | tr '\0' x)" 'Content-Type: application/json'
assert_eq "$STATUS" 413 "oversized body is refused"
request POST /auth/logout '' "X-Clog-CSRF: ${nonce}"
assert_eq "$STATUS" 200 "logout succeeds"
request GET /auth/session
assert_eq "$(jq -r .userId <<< "$BODY" 2> /dev/null)" 0 "logout ends the session"

throttled=false
for i in $(seq 0 9); do
  request GET /auth/login '' "X-Clog-Client-IP: 203.0.113.${i}"
  [[ "$STATUS" == 429 ]] && throttled=true
done
assert_eq "$throttled" true "forged client IP headers do not bypass throttling"

# ── Backup ───────────────────────────────────────────────────────────────────
podman run --rm "${PHP[@]}" "$PHP_IMAGE" "${CLI[@]}" backup /var/lib/clog/backup.sqlite > /dev/null
[[ -f "$WORK/data/backup.sqlite" ]] && ok "backup writes its file" || bad "backup writes its file" "missing"

finish
