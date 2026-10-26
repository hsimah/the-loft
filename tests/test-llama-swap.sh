#!/usr/bin/env bash
# test-llama-swap.sh — llama-swap.yaml must agree with itself and with the
# fetch commands in the Sputnik page: every model sits in exactly one router
# group, every group member is a defined model, every macro a model uses is
# defined, and each OCR model's weights are fetched by a documented command.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/tests/lib/assert.sh"
CONF="${ROOT}/services/sputnik/llama-swap.yaml"
DOC="${ROOT}/docs/services/sputnik.md"

models="$(sed -n '/^models:/,/^[a-z]/p' "$CONF" | sed -nE 's/^  "([^"]+)":$/\1/p' | sort)"
members="$(sed -n '/^routing:/,$p' "$CONF" | sed -nE 's/^ +- "([^"]+)"$/\1/p' | sort)"
macros="$(sed -n '/^macros:/,/^models:/p' "$CONF" | sed -nE 's/^  "([^"]+)": >$/\1/p' | sort)"

assert_eq "$members" "$models" "every model is in exactly one router group"
assert_eq "$(sort -u <<< "$members" | wc -l)" "$(wc -l <<< "$members")" "no model is in two groups"

used="$(sed -n '/^models:/,/^routing:/p' "$CONF" | grep -oE '\$\{[a-z][a-z-]*\}' | tr -d '${}' | sort -u)"
undefined="$(comm -23 <(printf '%s\n' "$used") <(printf '%s\n' "$macros"))"
assert_eq "$undefined" "" "every macro a model uses is defined"

# The OCR models stay loaded: persistent, and they leave other groups alone.
ocr="$(sed -n '/"ocr":/,/members:/p' "$CONF")"
assert_contains "$ocr" "persistent: true" "the OCR group is persistent"
assert_contains "$ocr" "exclusive: false" "loading OCR does not unload the large model"
assert_contains "$ocr" "swap: false" "the OCR models do not swap each other out"

# Every --model / --mmproj path is fetched by a documented command into the
# directory it is read from.
while IFS= read -r path; do
  dir="$(basename "$(dirname "$path")")"
  file="$(basename "$path")"
  assert_contains "$(cat "$DOC")" "$dir" "${file}: ${dir} is a fetch destination in the Sputnik page"
done < <(sed -n '/"glm-ocr":/,$p' "$CONF" | grep -oE '/models/[^ ]+\.gguf')

finish
