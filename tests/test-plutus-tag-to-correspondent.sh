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
  *tags/?name__iexact=Short) one 8 ;;
  *correspondents/?name__iexact=Seattle%20City%20Light) one 10 ;;
  *documents/?*tags__id__in=7\&*) printf '{"count":0,"results":[]}\n' ;;
  *documents/?*tags__id__in=8\&*) printf '{"count":5,"results":[{"id":1,"correspondent":null}]}\n' ;;
  *documents/?*) printf '{"count":4,"results":[%s]}\n' \
    '{"id":1,"correspondent":null},{"id":2,"correspondent":null},{"id":3,"correspondent":null},{"id":4,"correspondent":2}' ;;
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
assert_file "$WORK/merge/posts" '{"documents":[1,2,3],"method":"set_correspondent","parameters":{"correspondent":9}}' "sets the correspondent on every unassigned match"
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

out="$(run short Meta Short)"
assert_fails $? "a partial page fails"
assert_contains "$out" "returned 1 of 5 documents" "and says so"
assert_missing "$WORK/short/posts" "and posts nothing"

out="$(run badtag Meta Nope)"
assert_fails $? "an unknown tag fails"
assert_missing "$WORK/badtag/posts" "before posting"

finish
