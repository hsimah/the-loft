#!/usr/bin/env bash
# image-updates.sh — report newer registry tags for every image pinned in the
# repo (Compose image: lines and Dockerfile FROM lines). Workstation tool:
# anonymous Docker Hub/GHCR queries only; changes nothing.
#
# Usage: control-plane/image-updates.sh [-a]   (-a also lists current pins)
#
# Candidates have the same tag shape as the pin (digit runs vary, words stay),
# so 1.30.4-alpine is compared with 1.31.7-alpine, not 1.31.7-bookworm.
# "minor" and "major" are the newest tags sharing the pin's first two or first
# number. Tags that start with a commit hash are ordered by push date (Docker
# Hub only). Digest pins are compared with the tag's current digest. Read
# docs/operations/upgrades.md for held pins before acting on the output.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACCEPT='application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'

# Print "ref<TAB>file" for every pinned image.
scan() {
  local f
  grep -rHE '^\s*image:' "$ROOT/services" "$ROOT/hosts" --include='*.yml' \
    | sed -E 's/^([^:]+):\s*image:\s*"?([^"[:space:]]+)"?.*/\2\t\1/'
  while IFS= read -r f; do
    awk -v f="$f" '
      /^ARG [A-Za-z_]+=/ { split(substr($0, 5), kv, "="); arg[kv[1]] = kv[2] }
      /^FROM / {
        ref = $2
        for (k in arg) gsub("\\$\\{" k "\\}", arg[k], ref)
        if (ref ~ /:/ && !(ref in stage)) print ref "\t" f
        if (toupper($3) == "AS") stage[$4] = 1
      }' "$f"
  done < <(find "$ROOT/services" "$ROOT/hosts" -name 'Dockerfile*' -type f)
}

# Anchored ERE matching tags of the same shape as $1.
tag_pattern() {
  local tag=$1 out='' c
  while [[ -n $tag ]]; do
    if [[ $tag =~ ^([0-9a-f]{7,})([^0-9a-z]|$) && ${BASH_REMATCH[1]} == *[a-f]* ]]; then
      out+='[0-9a-f]+'; tag=${tag:${#BASH_REMATCH[1]}}
    elif [[ $tag =~ ^[0-9]+ ]]; then
      out+='[0-9]+'; tag=${tag:${#BASH_REMATCH[0]}}
    elif [[ $tag =~ ^[A-Za-z]+ ]]; then
      out+=${BASH_REMATCH[0]}; tag=${tag:${#BASH_REMATCH[0]}}
    else
      c=${tag:0:1}; [[ $c == [.+] ]] && out+="\\$c" || out+=$c; tag=${tag:1}
    fi
  done
  printf '^%s$' "$out"
}

# As tag_pattern, with the pin's first $2 numbers fixed.
fixed_pattern() { # tag count
  local pat rest i
  pat=$(tag_pattern "$1"); rest=$1
  for ((i = 0; i < $2; i++)); do
    [[ $rest =~ [0-9]+ ]] || return 1
    pat=${pat/'[0-9]+'/@${BASH_REMATCH[0]}@}
    rest=${rest#*"${BASH_REMATCH[0]}"}
  done
  printf '%s' "${pat//@/}"
}

# "registry repo" for an image name, e.g. "hub library/nginx".
locate() {
  local name=$1
  case $name in
    ghcr.io/*) echo "ghcr ${name#ghcr.io/}" ;;
    lscr.io/*) echo "ghcr ${name#lscr.io/}" ;;
    docker.io/*) locate "${name#docker.io/}" ;;
    *.*/*) echo "other $name" ;;
    *) [[ $name == */* ]] || name="library/$name"; echo "hub $name" ;;
  esac
}

# Retry transient registry errors; parallel checks trip rate limits.
get() { curl -fsS --retry 4 --retry-all-errors --retry-delay 2 "$@"; }

token() { # registry repo
  local j
  case $1 in
    hub) j=$(get "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$2:pull") ;;
    ghcr) j=$(get "https://ghcr.io/token?scope=repository:$2:pull") ;;
  esac || return 1
  jq -er .token <<< "$j"
}

# All tags; Docker Hub output is newest push first. Fails rather than
# returning a partial list.
tags() { # registry repo tag
  local reg=$1 repo=$2 tag=$3 url tok hdr filter page pages=0
  case $reg in
    ghcr)
      tok=$(token ghcr "$repo") || return 1
      url="https://ghcr.io/v2/${repo}/tags/list?n=10000"
      hdr=$(mktemp)
      while [[ -n $url ]]; do
        page=$(get -D "$hdr" -H "Authorization: Bearer $tok" "$url") || { rm -f "$hdr"; return 1; }
        jq -r '.tags[]?' <<< "$page"
        url=$(sed -nE 's/^[Ll]ink: <([^>]+)>.*/\1/p' "$hdr" | tr -d '\r')
        [[ -n $url ]] && url="https://ghcr.io${url}"
      done
      rm -f "$hdr" ;;
    hub)
      # Narrow by the tag's longest non-numeric end to keep paging short.
      local pre=${tag%%[0-9]*} suf=${tag##*[0-9]}
      filter=$([[ ${#pre} -ge ${#suf} ]] && echo "$pre" || echo "$suf")
      url="https://hub.docker.com/v2/repositories/${repo}/tags?page_size=100&ordering=last_updated&name=${filter}"
      while [[ -n $url && $url != null && $pages -lt 10 ]]; do
        page=$(get "$url") || return 1
        jq -r '.results[].name' <<< "$page"
        url=$(jq -r .next <<< "$page"); pages=$((pages + 1))
      done ;;
  esac
}

digest() { # registry repo tag
  local host tok
  case $1 in hub) host=registry-1.docker.io ;; ghcr) host=ghcr.io ;; esac
  tok=$(token "$1" "$2") || return 1
  get -I -H "Authorization: Bearer $tok" -H "Accept: $ACCEPT" \
    "https://${host}/v2/$2/manifests/$3" | sed -nE 's/^[Dd]ocker-[Cc]ontent-[Dd]igest: *([^[:space:]]+).*/\1/p'
}

newest() { # pattern by-date < tags
  if [[ $2 == date ]]; then grep -E "$1" | head -1; else grep -E "$1" | sort -V | tail -1; fi || true
}

check() { # ref files
  local ref=$1 files=$2 name tag pin='' reg repo all order=version latest='' major='' minor='' dig='' note=''
  name=${ref%@*}; [[ $ref == *@* ]] && pin=${ref#*@}
  tag=${name##*:}; name=${name%:*}
  read -r reg repo < <(locate "$name")
  if [[ $reg == other ]]; then
    row '?' "$name" "$tag" '' '' '' 'unsupported registry' "$files"; return
  fi
  if [[ $tag =~ ^[0-9a-f]{7,}- ]]; then
    order=date
    # linuxserver publishes the same tags to Docker Hub, which has push dates.
    [[ $repo == linuxserver/* ]] && reg=hub
  fi
  if ! all=$(tags "$reg" "$repo" "$tag" 2> /dev/null) || [[ -z $all ]]; then
    row '?' "$name" "$tag" '' '' '' 'no tags (local build?)' "$files"; return
  fi
  if [[ $tag =~ [0-9] ]]; then
    latest=$(newest "$(tag_pattern "$tag")" "$order" <<< "$all")
    if [[ $order == version ]]; then
      minor=$(fixed_pattern "$tag" 2) && minor=$(newest "$minor" version <<< "$all") || minor=''
      major=$(fixed_pattern "$tag" 1) && major=$(newest "$major" version <<< "$all") || major=''
    fi
    [[ $major == "$latest" || $major == "$tag" ]] && major=''
    [[ $minor == "$latest" || $minor == "$major" || $minor == "$tag" ]] && minor=''
    [[ $latest == "$tag" ]] && latest=''
  fi
  if [[ -n $pin ]]; then
    dig=$(digest "$reg" "$repo" "$tag" 2> /dev/null || true)
    if [[ -z $dig ]]; then note='digest lookup failed'
    elif [[ $dig != "$pin" ]]; then note="digest moved: $dig"
    fi
  fi
  if [[ -n $latest || -n $major || -n $minor || -n $note ]]; then
    row '->' "$name" "$tag" "$minor" "$major" "$latest" "$note" "$files"
  elif [[ $SHOW_ALL == 1 ]]; then
    row ok "$name" "$tag" '' '' '' '' "$files"
  fi
}

# Empty cells become "-" so column(1) keeps them.
row() {
  local c out=()
  for c in "$@"; do out+=("${c:--}"); done
  (IFS=$'\t'; printf '%s\n' "${out[*]}")
}

main() {
  SHOW_ALL=0
  [[ ${1:-} == -a ]] && SHOW_ALL=1
  local ref files out n=0
  out=$(mktemp -d); trap "rm -rf '$out'" EXIT
  while IFS=$'\t' read -r ref files; do
    n=$((n + 1)); check "$ref" "$files" > "$out/$(printf '%03d' "$n")" &
  done < <(scan | sed "s#\t$ROOT/#\t#" | sort -u \
    | awk -F'\t' '{ w[$1] = ($1 in w) ? w[$1] "," $2 : $2 } END { for (r in w) print r "\t" w[r] }' | sort)
  wait
  { row st image pinned minor major newest note where; cat "$out"/*; } | column -t -s $'\t'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
