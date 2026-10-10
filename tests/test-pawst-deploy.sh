#!/usr/bin/env bash
# test-pawst-deploy.sh — check pawst-deploy.sh resolves the release and digest
# from fake GitHub responses and hands them to a stubbed release puller.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/tests/lib/assert.sh"
require jq

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SCRIPT="$WORK/pawst-deploy.sh"
cp "${ROOT}/control-plane/pawst-deploy.sh" "$SCRIPT"
printf '#!/bin/sh\nexit 1\n' > "$WORK/github-app-token.sh"
chmod +x "$WORK/github-app-token.sh"
echo 'printf "%s\n" "$*" >> "$FIXTURE/pull-calls"; exit "${PULL_STATUS:-0}"' \
  > "$WORK/deploy-pull.sh"

MOCK_BIN="$WORK/bin"
mkdir -p "$MOCK_BIN"
# API calls print the fixture release; the local site check exits $SITE_STATUS.
mock curl 'printf "%s\n" "$*" >> "$FIXTURE/curl-calls"
case "$*" in *api.github.com*) cat "$FIXTURE/release.json" ;; *) exit "${SITE_STATUS:-0}" ;; esac'

DIGEST="$(printf '%064d' 7 | tr 0 a)"

release() { # tag digest [asset-count]
  jq -n --arg tag "$1" --arg digest "$2" --argjson n "${3:-1}" \
    '{tag_name: $tag, assets: [range($n) | {name: "site-\(.).tar.gz", digest: $digest}]
      + [{name: "notes.txt", digest: null}]}' > "$WORK/release.json"
}
deploy() { # args...; sets out and status
  rm -f "$WORK/curl-calls" "$WORK/pull-calls"
  out="$(PATH="$MOCK_BIN:$PATH" FIXTURE="$WORK" bash "$SCRIPT" "$@" 2>&1)"
  status=$?
}

# ── latest release ───────────────────────────────────────────────────────────
release deploy-2 "sha256:${DIGEST}"
deploy hblake
assert_eq "$status" 0 "deploys the latest release"
assert_contains "$(cat "$WORK/curl-calls")" "repos/hsimah-services/hblake/releases/latest" "asks GitHub for latest"
assert_file "$WORK/pull-calls" \
  "pawst-hblake hsimah-services/hblake /opt/pawst/prod/hblake  deploy-2 ${DIGEST}" \
  "passes tag and bare digest to the puller"
assert_contains "$(cat "$WORK/curl-calls")" "Host: hbla.ke" "checks the site afterwards"
assert_contains "$out" "hbla.ke serving deploy-2" "reports the live tag"

# ── explicit tag (rollback) ──────────────────────────────────────────────────
release deploy-1 "sha256:${DIGEST}"
deploy hsimah deploy-1
assert_eq "$status" 0 "deploys a given tag"
assert_contains "$(cat "$WORK/curl-calls")" "repos/hsimah-services/hsimah/releases/tags/deploy-1" "asks GitHub for that tag"
assert_contains "$(cat "$WORK/curl-calls")" "Host: hsimah.com" "checks the hsimah domain"

# ── no verify ────────────────────────────────────────────────────────────────
release deploy-2 "sha256:${DIGEST}"
SITE_STATUS=7 deploy --no-verify hblake
assert_eq "$status" 0 "--no-verify skips the site check"
assert_absent "$(cat "$WORK/curl-calls")" "Host:" "no local request"

# ── refusals ─────────────────────────────────────────────────────────────────
deploy pupyrus
assert_fails "$status" "rejects an unknown site"
assert_missing "$WORK/curl-calls" "unknown site makes no requests"

deploy hblake one two
assert_fails "$status" "rejects extra arguments"

release deploy-3 ""
deploy hblake
assert_fails "$status" "rejects a release without a digest"
assert_missing "$WORK/pull-calls" "missing digest deploys nothing"

release deploy-3 "sha256:${DIGEST}" 2
deploy hblake
assert_fails "$status" "rejects more than one archive"
assert_missing "$WORK/pull-calls" "ambiguous asset deploys nothing"

release deploy-2 "sha256:${DIGEST}"
PULL_STATUS=1 deploy hblake
assert_fails "$status" "puller failure fails the deploy"
assert_absent "$(cat "$WORK/curl-calls")" "Host:" "failed pull skips the site check"

SITE_STATUS=22 deploy hblake
assert_fails "$status" "site check failure fails the deploy"
assert_contains "$out" "did not serve index.html" "explains the failed check"

# ── entry point ──────────────────────────────────────────────────────────────
LC="$WORK/loft-ctl-root"
mkdir -p "$LC/hosts/viking" "$LC/control-plane" "$LC/bin"
cp "${ROOT}/loft-ctl" "$LC/"
cp "${ROOT}/control-plane/common.sh" "$LC/control-plane/"
echo 'SERVICES=(mushr pawst clog)' > "$LC/hosts/viking/host.conf"
printf '#!/bin/sh\necho viking\n' > "$LC/bin/hostname"
printf '#!/bin/sh\necho sudo "$@"\n' > "$LC/bin/sudo"
chmod +x "$LC/bin/"*
out="$(PATH="$LC/bin:$PATH" "$BASH" "$LC/loft-ctl" deploy pawst hblake 2>&1)"
assert_eq "$?" 0 "loft-ctl routes pawst deploys"
assert_eq "$out" "sudo bash ${LC}/control-plane/pawst-deploy.sh hblake" "loft-ctl runs pawst-deploy.sh under sudo"
out="$(PATH="$LC/bin:$PATH" "$BASH" "$LC/loft-ctl" deploy pupyrus 2>&1)"
assert_fails "$?" "loft-ctl rejects other apps"

finish
