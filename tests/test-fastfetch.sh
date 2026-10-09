#!/usr/bin/env bash
# test-fastfetch.sh — render the fleet fastfetch config with its real modules,
# relocating only the logo asset.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/tests/lib/assert.sh"
require fastfetch jq

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

jq --arg logo "${ROOT}/laiko.txt" '.logo.source = $logo' "${ROOT}/fastfetch.jsonc" > "$WORK/config.jsonc"
out="$(timeout 30 fastfetch --config "$WORK/config.jsonc" --pipe false 2>&1)"
assert_eq "$?" 0 "fastfetch renders the config"
out="$(sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g' <<< "$out")"

missing=0
while IFS= read -r line; do
  line="$(sed -E 's/\$[1-9]//g; s/[[:space:]]+$//' <<< "$line")"
  case "$out" in *"$line"*) ;; *) missing=$((missing + 1)) ;; esac
done < "${ROOT}/laiko.txt"
assert_eq "$missing" 0 "every Laiko logo line is displayed"

for label in OS: Kernel: CPU: Memory:; do
  assert_contains "$out" "$label" "shows ${label%:}"
done

finish
