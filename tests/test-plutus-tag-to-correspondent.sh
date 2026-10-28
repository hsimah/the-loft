#!/usr/bin/env bash
# test-plutus-tag-to-correspondent.sh — run the tag-to-correspondent script
# against a mocked Paperless API. No network.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/control-plane/plutus-tag-to-correspondent.sh"
source "${ROOT}/tests/lib/assert.sh"
require jq

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

# Mock curl: record argv and any POST body, answer by URL.
cat > "$WORK/bin/curl" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_DIR/argv"
prev=""
for a in "$@"; do
  case "$a" in http*) url="$a" ;; esac
  [[ "$prev" == --data ]] && printf '%s\n' "$a" >> "$MOCK_DIR/posts"
  prev="$a"
done
one() { printf '{"count":1,"results":[{"id":%s}]}\n' "$1"; }
case "$url" in
  *tags/?name__iexact=Meta) one 5 ;;
  *tags/?name__iexact=Facebook) one 6 ;;
  *tags/?name__iexact=Seattle%20City%20Light) one 7 ;;
  *correspondents/?name__iexact=Meta) one 9 ;;
  *correspondents/?name__iexact=Seattle%20City%20Light) one 10 ;;
  *documents/?*tags__id__in=7\&*) printf '{"count":0,"all":[]}\n' ;;
  *documents/?*) printf '{"count":3,"all":[1,2,3]}\n' ;;
  *bulk_edit/) printf '{"result":"OK"}\n' ;;
  *) printf '{"count":0,"results":[]}\n' ;;
esac
MOCK
chmod +x "$WORK/bin/curl"

run() { # case args...; echoes combined output and leaves the mock's records
  local dir="$WORK/$1"; shift
  mkdir -p "$dir"
  MOCK_DIR="$dir" PATH="$WORK/bin:$PATH" PLUTUS_TOKEN=s3cret PLUTUS_URL=https://plutus.test \
    bash "$SCRIPT" "$@" 2>&1
}

out="$(run merge Meta Meta Facebook)"
argv="$(cat "$WORK/merge/argv")"
assert_contains "$argv" "tags__id__in=5,6&correspondent__isnull=1" "matches any of the tags, unassigned only"
assert_file "$WORK/merge/posts" '{"documents":[1,2,3],"method":"set_correspondent","parameters":{"correspondent":9}}' "sets the correspondent on every match"
assert_contains "$out" "Meta: 3 documents" "reports the count"
assert_absent "$argv" "s3cret" "the token never appears in argv"

run default Meta > /dev/null
assert_contains "$(cat "$WORK/default/argv")" "tags__id__in=5&" "the tag defaults to the correspondent's name"

out="$(run spaces "Seattle City Light")"
assert_contains "$out" "Seattle City Light: 0 documents" "names with spaces are encoded"
assert_missing "$WORK/spaces/posts" "nothing to set posts nothing"

run dry --dry-run Meta > /dev/null
assert_missing "$WORK/dry/posts" "--dry-run posts nothing"

out="$(run missing Nobody)"
assert_fails $? "an unknown correspondent fails"
assert_contains "$out" "no single correspondents named 'Nobody'" "and says which"
assert_missing "$WORK/missing/posts" "and posts nothing"

out="$(run badtag Meta Nope)"
assert_fails $? "an unknown tag fails"
assert_missing "$WORK/badtag/posts" "before posting"

finish
