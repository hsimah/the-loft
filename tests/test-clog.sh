#!/usr/bin/env bash
# test-clog.sh — Clog release staging and effective service isolation.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/tests/lib/assert.sh"
require jq

STAGER="${ROOT}/services/clog/stage-release.sh"
REQUIRED=(server/standalone/public/index.php server/standalone/cli.php
  server/vendor/autoload.php client/dist/.vite/manifest.json client/dist/assets/stylex.css)
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A fresh case dir with a valid release tree in $SRC; sets CASE and SRC.
fresh() {
  local f
  CASE="$(mktemp -d "$WORK/case.XXXXXX")"
  SRC="$CASE/src"
  for f in "${REQUIRED[@]}"; do mkdir -p "$SRC/$(dirname "$f")"; echo -n '{}' > "$SRC/$f"; done
}
# Archive $SRC (required files, then any extra tar args); sets ARCHIVE and DIGEST.
bundle() {
  ARCHIVE="$CASE/release.tar.gz"
  tar -C "$SRC" -czf "$ARCHIVE" "${REQUIRED[@]}" "$@"
  DIGEST="$(sha256sum "$ARCHIVE" | cut -d' ' -f1)"
}
stage() { # digest [--reuse]; sets out and status
  out="$(bash "$STAGER" "$ARCHIVE" "$1" --releases "$CASE/releases" "${@:2}" 2>&1)"
  status=$?
}

# ── staging ──────────────────────────────────────────────────────────────────
fresh; bundle
stage "$DIGEST"
assert_eq "$status" 0 "valid archive stages"
release="$out"
assert_eq "${release##*/}" "$DIGEST" "release is named after its digest"
assert_eq "$(stat -c %a "$release")" 755 "release directory is readable"
stage "$DIGEST"
assert_fails "$status" "an existing release is never overwritten"

stage "$DIGEST" --reuse
assert_eq "$out" "$release" "reuse accepts an identical release"
echo -n modified > "$release/server/standalone/cli.php"
stage "$DIGEST" --reuse
assert_fails "$status" "reuse rejects a modified release"
assert_contains "$out" "differs" "explains the mismatch"

fresh; bundle
stage "$(printf '0%.0s' {1..64})"
assert_fails "$status" "checksum mismatch fails"
assert_missing "$CASE/releases" "checksum mismatch stages nothing"

# ── unsafe entries ───────────────────────────────────────────────────────────
unsafe() { # label tar-args...
  local label="$1"; shift
  bundle "$@"
  stage "$DIGEST"
  assert_fails "$status" "${label} is rejected"
  assert_eq "$(ls -A "$CASE/releases" 2> /dev/null)" "" "${label} leaves no release"
}
fresh; echo -n x > "$SRC/escaped"
unsafe "parent traversal" -P --transform 's,^escaped$,../escaped,' escaped
fresh; echo -n x > "$SRC/escaped"
unsafe "absolute path" -P --transform 's,^escaped$,/tmp/escaped,' escaped
fresh; ln -s /etc/passwd "$SRC/server/link"
unsafe "symlink" server/link
fresh; ln "$SRC/server/vendor/autoload.php" "$SRC/server/hardlink"
unsafe "hard link" server/hardlink

# ── effective service boundary ───────────────────────────────────────────────
if command -v docker > /dev/null; then
  c="$(cd "$ROOT" && docker compose -f services/clog/docker-compose.yml --profile tools config --format json)"
  q() { jq -c "$1" <<< "$c"; }
  assert_eq "$(q '.services | keys')" '["clog","clog-cli","clog-php"]' "clog runs nginx, php and the CLI"
  assert_eq "$(q '[.services[] | (has("ports") or has("build") | not) and .read_only == true
    and .user == "1003:1003" and .cap_drop == ["ALL"]] | all')" true "every service is unpublished, read-only and unprivileged"
  assert_eq "$(q '.services.clog | (.volumes | map({key: .target, value: .}) | from_entries) as $m
    | [(.networks | keys), ($m | has("/var/lib/clog") or has("/opt/clog")), $m["/run/clog"].read_only]')" \
    '[["clog-prod"],false,true]' "nginx is only on clog-prod, without data or code, with a read-only socket"
  assert_eq "$(q '[.services | to_entries[] | select(.key != "clog") | .value
    | (.volumes | map({key: .target, value: .}) | from_entries) as $m
    | .network_mode == "none" and $m["/opt/clog"].read_only == true and ($m["/var/lib/clog"].read_only // false) == false] | all')" \
    true "php and the CLI have no network, read-only code and writable data"
  assert_eq "$(q '.networks["clog-prod"].external')" true "clog-prod is external"
else
  printf 'skip   docker not installed; isolation checks skipped\n'
fi

finish
