#!/usr/bin/env bash
# paperless-warm-suggestions.sh — fill Paperless's AI suggestion cache for the
# first N inbox documents, so working through them in the UI does not wait a
# minute or more on each. Run it as the user who will do the triage: the cache
# is per user and expires after 50 minutes, but a hit refreshes it, so after the
# first pass the script re-requests every INTERVAL seconds until stopped.
# Documents are taken in ascending id order, so work through them in that order
# (sort the inbox view by ID, ascending). Run it in tmux before a session.
#
#   control-plane/paperless-warm-suggestions.sh [N] [INTERVAL]
#
# N defaults to 100, INTERVAL to 1800. The API token (Profile → API Auth Token)
# comes from PAPERLESS_TOKEN, else GPT_PAPERLESS_TOKEN in services/mercurius/.env,
# else a prompt. The cache belongs to the token's user, so that must be the user
# who works the inbox in the UI. PAPERLESS_URL overrides the address.
set -euo pipefail

URL="${PAPERLESS_URL:-https://paperless.loft.hsimah.com}"
n="${1:-100}"
interval="${2:-1800}"
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
[[ "$n" =~ ^[0-9]+$ && "$n" -gt 0 ]] || die "usage: ${0##*/} [N] [INTERVAL]"
[[ "$interval" =~ ^[0-9]+$ && "$interval" -gt 0 ]] || die "usage: ${0##*/} [N] [INTERVAL]"

ENV_FILE="$(dirname "${BASH_SOURCE[0]}")/../services/mercurius/.env"
if [[ -z "${PAPERLESS_TOKEN:-}" && -r "$ENV_FILE" ]]; then
  PAPERLESS_TOKEN="$(sed -n 's/^GPT_PAPERLESS_TOKEN=//p' "$ENV_FILE" | tail -n1)"
fi
if [[ -z "${PAPERLESS_TOKEN:-}" ]]; then
  read -rsp 'Paperless API token: ' PAPERLESS_TOKEN < /dev/tty
  echo >&2
fi

api() { # path [curl args...]; the header file keeps the token out of argv
  local path="$1"; shift
  curl -fsS -H @<(printf 'Authorization: Token %s\n' "$PAPERLESS_TOKEN") \
    -H 'Accept: application/json' "$@" "${URL}/api/${path}"
}

mapfile -t ids < <(api "documents/?is_in_inbox=true&ordering=id&page_size=${n}&fields=id" \
  | jq -r '.results[].id')
[[ ${#ids[@]} -gt 0 ]] || die "no inbox documents"
printf 'warming %s documents (ids %s to %s), refresh every %ss\n' \
  "${#ids[@]}" "${ids[0]}" "${ids[-1]}" "$interval"

pass=1
while :; do
  ok=0 failed=0
  for id in "${ids[@]}"; do
    start=$SECONDS
    # Requests queue behind llama-swap's one slot; Paperless's own timeout is 300 s.
    if api "documents/${id}/ai_suggestions/" --max-time 400 > /dev/null; then
      ok=$((ok + 1))
      printf '%s pass %s: %s ok (%ss)\n' "$(date +%T)" "$pass" "$id" "$((SECONDS - start))"
    else
      failed=$((failed + 1))
      printf '%s pass %s: %s FAILED\n' "$(date +%T)" "$pass" "$id" >&2
    fi
  done
  printf '%s pass %s done: %s ok, %s failed; next in %ss\n' \
    "$(date +%T)" "$pass" "$ok" "$failed" "$interval"
  pass=$((pass + 1))
  sleep "$interval"
done
