#!/usr/bin/env bash
# assert.sh — shared helpers for tests/test-*.sh. Source it after `set -uo
# pipefail`; call `finish` last so the script's status reflects failures.

PASS=0
FAIL=0

ok()  { printf 'ok     %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf 'FAIL   %s\n     %s\n' "$1" "$2" >&2; FAIL=$((FAIL + 1)); }

assert_eq() { # actual expected label
  [[ "$1" == "$2" ]] && ok "$3" || bad "$3" "got '$1', wanted '$2'"
}
assert_contains() { # haystack needle label
  case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "expected to find: $2" ;; esac
}
assert_absent() { # haystack needle label
  case "$1" in *"$2"*) bad "$3" "did not expect: $2" ;; *) ok "$3" ;; esac
}
assert_fails() { # status label
  [[ "$1" -ne 0 ]] && ok "$2" || bad "$2" "exited 0, wanted failure"
}
assert_missing() { # path label
  [[ -e "$1" || -L "$1" ]] && bad "$2" "unexpected: $1" || ok "$2"
}
assert_file() { # path expected-content label
  if [[ -f "$1" ]]; then assert_eq "$(cat "$1")" "$2" "$3"; else bad "$3" "missing: $1"; fi
}

# Exit 0 with a note when a tool the whole file needs is absent.
require() { # command...
  local c
  for c in "$@"; do
    command -v "$c" > /dev/null || { printf 'skip   %s not installed\n' "$c"; exit 0; }
  done
}

# Write an executable stub to $MOCK_BIN, which the test puts first on PATH.
mock() { # name body
  printf '#!/bin/bash\n%s\n' "$2" > "${MOCK_BIN:?}/$1"
  chmod +x "${MOCK_BIN}/$1"
}

finish() {
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  [[ "$FAIL" -eq 0 ]]
}
