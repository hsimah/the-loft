#!/usr/bin/env bash
# test-image-updates.sh — tag-shape matching and repo scan; no network.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/tests/lib/assert.sh"
source "${ROOT}/control-plane/image-updates.sh"
set +e

TAGS='1.30.4-alpine
1.30.6-alpine
1.31.7-alpine
1.31.7-bookworm
2.0.0-alpine
1.30.10-alpine-slim'

latest=$(newest "$(tag_pattern 1.30.4-alpine)" version <<< "$TAGS")
assert_eq "$latest" 2.0.0-alpine "newest keeps the tag's words"
assert_eq "$(newest "$(fixed_pattern 1.30.4-alpine 1)" version <<< "$TAGS")" 1.31.7-alpine "major fixes the first number"
assert_eq "$(newest "$(fixed_pattern 1.30.4-alpine 2)" version <<< "$TAGS")" 1.30.6-alpine "minor fixes two numbers"
fixed_pattern 9 2 > /dev/null; assert_fails $? "minor needs two numbers"
assert_eq "$(tag_pattern afe0394f-ls358)" '^[0-9a-f]+-ls[0-9]+$' "leading hash is one token"
assert_eq "$(tag_pattern 1.43.4.10903-e5521bd8c)" '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9a-f]+$' "trailing hash"
assert_eq "$(newest "$(tag_pattern afe0394f-ls358)" date <<< $'fffbb45b-ls26\nafe0394f-ls358')" fffbb45b-ls26 "hash tags take the first (newest) push"

assert_eq "$(locate nginx)" "hub library/nginx" "official image"
assert_eq "$(locate docker.io/valkey/valkey)" "hub valkey/valkey" "docker.io prefix"
assert_eq "$(locate lscr.io/linuxserver/radarr)" "ghcr linuxserver/radarr" "lscr via ghcr"
assert_eq "$(locate quay.io/x/y)" "other quay.io/x/y" "unsupported registry"

refs=$(scan | cut -f1)
assert_contains "$refs" "caddy:$(sed -nE 's/^ARG CADDY_VERSION=//p' "$ROOT/services/mushr/Dockerfile.caddy")-builder" "Dockerfile ARG expanded"
assert_absent "$refs" 'builder:' "build stages skipped"
assert_contains "$refs" "plexinc/pms-docker:" "Compose images found"

finish
