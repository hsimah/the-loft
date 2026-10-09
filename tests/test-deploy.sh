#!/usr/bin/env bash
# test-deploy.sh — run the real release puller against fake GitHub responses
# served by a mocked curl.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/tests/lib/assert.sh"
require jq rsync flock

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
STATE="$WORK/state"
SCRIPT="$WORK/deploy-pull.sh"
sed "s#^STATE_DIR=\"/var/lib/loft/deploy\"#STATE_DIR=\"${STATE}\"#" \
  "${ROOT}/control-plane/deploy-pull.sh" > "$SCRIPT"
cp "${ROOT}/control-plane/extract-release.sh" "$WORK/"
printf '#!/bin/sh\nexit 1\n' > "$WORK/github-app-token.sh"
chmod +x "$WORK/github-app-token.sh"

MOCK_BIN="$WORK/bin"
mkdir -p "$MOCK_BIN"
mock curl 'printf "%s\n" "$*" >> "$FIXTURE/calls"
while [[ $# -gt 0 ]]; do
  if [[ "$1" == -o ]]; then cp "$FIXTURE/asset.tar.gz" "$2"; exit; fi
  shift
done
cat "$FIXTURE/release.json"'

TARGET="$WORK/site"
SRC="$WORK/src"

reset_site() {
  rm -rf "$TARGET" "$STATE" "$WORK/calls" "$WORK/escape"
  mkdir -p "$TARGET"
  echo -n old > "$TARGET/index.html"
}

# Fill $SRC with name=content pairs; a value of @ makes a symlink to /etc/passwd.
src() {
  local entry
  rm -rf "$SRC"; mkdir -p "$SRC"
  for entry in "$@"; do
    mkdir -p "$SRC/$(dirname "${entry%%=*}")"
    if [[ "${entry#*=}" == @ ]]; then ln -s /etc/passwd "$SRC/${entry%%=*}"
    else printf '%s' "${entry#*=}" > "$SRC/${entry%%=*}"; fi
  done
}

# Archive $SRC as the release asset; sets DIGEST.
release() { # tag asset-count tar-args...
  local tag="$1" count="$2"; shift 2
  tar -C "$SRC" -czf "$WORK/asset.tar.gz" "$@"
  jq -n --arg tag "$tag" --argjson n "$count" \
    '{tag_name: $tag, assets: [range($n) | {name: "asset-\(.).tar.gz", url: "https://fixture/asset"}]}' \
    > "$WORK/release.json"
  DIGEST="$(sha256sum "$WORK/asset.tar.gz" | cut -d' ' -f1)"
}

deploy() { # tag digest; sets out and status
  out="$(PATH="$MOCK_BIN:$PATH" FIXTURE="$WORK" \
    bash "$SCRIPT" test-site owner/repo "$TARGET" '' "$1" "$2" 2>&1)"
  status=$?
}

# ── promotion, then rollback to an older release ─────────────────────────────
reset_site
inode="$(stat -c %i "$TARGET")"
src site/index.html=new site/.hidden=preserved
release v2 1 site
deploy v2 "$DIGEST"
assert_eq "$status" 0 "promotes a release"
assert_file "$TARGET/.hidden" preserved "keeps dotfiles from the archive"
assert_eq "$(stat -c %i "$TARGET")" "$inode" "keeps the target inode (bind mounts survive)"
src index.html=known-good
release v1 1 index.html
deploy v1 "$DIGEST"
assert_eq "$status" 0 "rolls back to an older release"
assert_file "$TARGET/index.html" known-good "rollback replaces content"
assert_missing "$TARGET/.hidden" "rollback removes files absent from the release"
assert_contains "$(cat "$WORK/calls")" "/releases/tags/v1" "fetches the pinned tag"
assert_file "$STATE/test-site.version" v1 "records the deployed version"

# ── forced restore ───────────────────────────────────────────────────────────
reset_site
src site/index.html=new
release v2 1 site
deploy v2 "$DIGEST"
rm "$TARGET/index.html"
out="$(PATH="$MOCK_BIN:$PATH" FIXTURE="$WORK" LOFT_FORCE_DEPLOY=1 \
  bash "$SCRIPT" test-site owner/repo "$TARGET" '' v2 "$DIGEST" 2>&1)"
assert_eq "$?" 0 "forced restore succeeds despite matching state"
assert_file "$TARGET/index.html" new "forced restore repairs content"

# ── checksum failure ─────────────────────────────────────────────────────────
reset_site
release v2 1 site
deploy v2 "$(printf '0%.0s' {1..64})"
assert_fails "$status" "checksum mismatch fails"
assert_file "$TARGET/index.html" old "checksum mismatch leaves content"
assert_missing "$STATE/test-site.version" "checksum mismatch leaves state"

# ── unsafe or incomplete archives ────────────────────────────────────────────
unsafe() { # label tar-args...
  local label="$1"; shift
  reset_site
  release v2 1 "$@"
  deploy v2 "$DIGEST"
  assert_fails "$status" "${label} is rejected"
  assert_file "$TARGET/index.html" old "${label} never reaches the target"
  assert_missing "$WORK/escape" "${label} writes nothing outside staging"
}
src escape=bad
unsafe "path traversal" -P --transform 's,^escape$,../escape,' escape
src index.html=@
unsafe "symlink" index.html
src data.txt=no-index
unsafe "archive without index.html" data.txt

# ── ambiguous assets and tag mismatch ────────────────────────────────────────
reset_site
src site/index.html=new
release v2 2 site
deploy v2 "$DIGEST"
assert_fails "$status" "two assets are ambiguous"
release v3 1 site
deploy v2 "$DIGEST"
assert_fails "$status" "tag mismatch fails"

# ── pinning ──────────────────────────────────────────────────────────────────
reset_site
release v2 1 site
deploy v2 ''
assert_fails "$status" "pinned release without checksum fails"
assert_missing "$WORK/calls" "no download without a checksum"

deploy '' ''
assert_fails "$status" "unpinned deployment is refused"
assert_contains "$out" "require a release tag" "explains the refusal"
assert_missing "$WORK/calls" "no download when unpinned"

# ── concurrent deployment ────────────────────────────────────────────────────
reset_site
mkdir -p "$STATE"
release v2 1 site
flock "$STATE/test-site.lock" sleep 10 &
HOLDER=$!
until ! flock -n "$STATE/test-site.lock" true; do :; done
deploy v2 "$DIGEST"
kill "$HOLDER" 2> /dev/null; wait "$HOLDER" 2> /dev/null
assert_fails "$status" "concurrent deployment is rejected"
assert_contains "$out" "Another deployment" "explains the lock"
assert_file "$TARGET/index.html" old "rejected deployment leaves content"

finish
