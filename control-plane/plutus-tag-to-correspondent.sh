#!/usr/bin/env bash
# plutus-tag-to-correspondent.sh — give every Plutus document that carries any
# of the tags, and has no correspondent yet, the named correspondent. For the
# tidy-up after a bulk import, where folder names arrive as tags
# (docs/services/plutus.md#bulk-import). The tags and the correspondent must
# already exist; the tags are left in place.
#
#   control-plane/plutus-tag-to-correspondent.sh [--dry-run] CORRESPONDENT [TAG...]
#
# TAG defaults to CORRESPONDENT. The API token (Profile → API Auth Token) comes
# from PLUTUS_TOKEN or a prompt; PLUTUS_URL overrides the address.
set -euo pipefail

URL="${PLUTUS_URL:-https://plutus.loft.hsimah.com}"
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

dry=false
[[ "${1:-}" == --dry-run ]] && { dry=true; shift; }
[[ $# -ge 1 ]] || die "usage: ${0##*/} [--dry-run] CORRESPONDENT [TAG...]"
name="$1"; shift
tags=("$@")
[[ ${#tags[@]} -gt 0 ]] || tags=("$name")

if [[ -z "${PLUTUS_TOKEN:-}" ]]; then
  read -rsp 'Plutus API token: ' PLUTUS_TOKEN < /dev/tty
  echo >&2
fi

api() { # path [curl args...]; the header file keeps the token out of argv
  local path="$1"; shift
  curl -fsS -H @<(printf 'Authorization: Token %s\n' "$PLUTUS_TOKEN") \
    -H 'Accept: application/json' "$@" "${URL}/api/${path}"
}
id_of() { # kind name → the id of the one object with that name, ignoring case
  local json
  json="$(api "$1/?name__iexact=$(jq -rn --arg s "$2" '$s|@uri')")"
  [[ "$(jq '.count' <<< "$json")" == 1 ]] || die "no single $1 named '$2'"
  jq '.results[0].id' <<< "$json"
}

cid="$(id_of correspondents "$name")"
tag_ids=()
for t in "${tags[@]}"; do
  id="$(id_of tags "$t")"
  tag_ids+=("$id")
done

# `all` lists every matching id regardless of page size.
docs="$(api "documents/?tags__id__in=$(IFS=,; echo "${tag_ids[*]}")&correspondent__isnull=1&page_size=1" | jq -c '.all')"
n="$(jq length <<< "$docs")"
printf '%s: %s documents tagged %s with no correspondent\n' "$name" "$n" "${tags[*]}"
[[ "$n" -gt 0 ]] && ! $dry || exit 0

api documents/bulk_edit/ -X POST -H 'Content-Type: application/json' \
  --data "$(jq -nc --argjson d "$docs" --argjson c "$cid" \
    '{documents: $d, method: "set_correspondent", parameters: {correspondent: $c}}')" > /dev/null
printf '%s: set\n' "$name"
