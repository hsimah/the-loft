#!/usr/bin/env bash
# run.sh — run every tests/test-*.sh; exit non-zero if any fails.
set -uo pipefail

TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=()
for t in "$TESTS"/test-*.sh; do
  printf '\n== %s\n' "${t##*/}"
  bash "$t" || failed+=("${t##*/}")
done

if [[ ${#failed[@]} -gt 0 ]]; then
  printf '\nFailed: %s\n' "${failed[*]}" >&2
  exit 1
fi
printf '\nAll test files passed\n'
