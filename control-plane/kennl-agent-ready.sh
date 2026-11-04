#!/usr/bin/env bash
# kennl-agent-ready.sh — make Forgejo repositories ready for the rodnik coding
# runner (docs/automation/coding-agents.md): copy the label set from a source
# repository, creating missing labels and correcting colour, description and
# exclusivity on existing ones, and give the agent account write access.
# Labels only in the target are left alone. Safe to re-run.
#
#   control-plane/kennl-agent-ready.sh [--dry-run] (--all | OWNER/REPO...)
#
# --all covers every repository the token can see, except pull mirrors and
# archived ones. The token (Settings → Applications; scopes read/write
# repository, and read user for --all; an admin token sees every repository)
# comes from KENNL_TOKEN or a prompt. KENNL_URL, KENNL_LABEL_SOURCE
# (default hsimah-services/listory) and KENNL_AGENT_USER (default rodnik)
# override the defaults.
set -euo pipefail

URL="${KENNL_URL:-https://kennl.loft.hsimah.com}"
SOURCE="${KENNL_LABEL_SOURCE:-hsimah-services/listory}"
AGENT="${KENNL_AGENT_USER:-rodnik}"
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
usage="usage: ${0##*/} [--dry-run] (--all | OWNER/REPO...)"

dry=false
[[ "${1:-}" == --dry-run ]] && { dry=true; shift; }
[[ $# -ge 1 ]] || die "$usage"
all=false
[[ "$1" == --all ]] && { all=true; shift; [[ $# -eq 0 ]] || die "$usage"; }

if [[ -z "${KENNL_TOKEN:-}" ]]; then
  read -rsp 'Forgejo API token: ' KENNL_TOKEN < /dev/tty
  echo >&2
fi

api() { # path [curl args...]; the header file keeps the token out of argv
  local path="$1"; shift
  curl -fsS -H @<(printf 'Authorization: token %s\n' "$KENNL_TOKEN") \
    -H 'Accept: application/json' "$@" "${URL}/api/v1/${path}"
}
send() { # method path json
  $dry && return 0
  api "$2" -X "$1" -H 'Content-Type: application/json' --data "$3" > /dev/null
}
paged() { # path [jq filter for the array in each page] → one JSON array
  local path="$1" filter="${2:-.}" page=1 batch out='[]' sep='?'
  [[ "$path" == *\?* ]] && sep='&'
  while :; do
    batch="$(api "${path}${sep}limit=50&page=${page}" | jq -c "$filter")"
    out="$(jq -c --argjson b "$batch" '. + $b' <<< "$out")"
    [[ "$(jq length <<< "$batch")" -eq 50 ]] || break
    page=$((page + 1))
  done
  printf '%s\n' "$out"
}
# Forgejo returns colours without '#'; compare them that way, lower case.
norm='{name, color: (.color | ltrimstr("#") | ascii_downcase), description: (.description // ""), exclusive: (.exclusive // false)}'

source_labels="$(paged "repos/${SOURCE}/labels" "[.[] | ${norm}]")"
[[ "$(jq length <<< "$source_labels")" -gt 0 ]] || die "${SOURCE} has no labels"

if $all; then
  mapfile -t repos < <(paged repos/search '[.data[] | select((.mirror or .archived) | not) | .full_name]' | jq -r '.[]')
else
  repos=("$@")
fi

$dry && echo '(dry run: nothing is changed)'
for repo in "${repos[@]}"; do
  [[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || die "not OWNER/REPO: $repo"
  echo "== ${repo}"

  if [[ "$repo" != "$SOURCE" ]]; then
    target_labels="$(paged "repos/${repo}/labels" "[.[] | {id} + ${norm}]")"
    while IFS= read -r want; do
      name="$(jq -r .name <<< "$want")"
      have="$(jq -c --arg n "$name" 'map(select(.name == $n)) | first // empty' <<< "$target_labels")"
      if [[ -z "$have" ]]; then
        echo "  label + ${name}"
        send POST "repos/${repo}/labels" "$want"
      elif [[ "$(jq -c 'del(.id)' <<< "$have")" != "$want" ]]; then
        echo "  label ~ ${name}"
        send PATCH "repos/${repo}/labels/$(jq .id <<< "$have")" "$want"
      fi
    done < <(jq -c '.[]' <<< "$source_labels")
  fi

  if [[ "${repo%%/*}" == "$AGENT" ]]; then
    continue
  fi
  permission="$(api "repos/${repo}/collaborators/${AGENT}/permission" 2> /dev/null | jq -r '.permission // "none"' || echo none)"
  case "$permission" in
    write | admin | owner) ;;
    *)
      echo "  ${AGENT}: ${permission} → write"
      send PUT "repos/${repo}/collaborators/${AGENT}" '{"permission": "write"}'
      ;;
  esac
done
