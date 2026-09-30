#!/usr/bin/env bash
# check-docs.sh — check local links and heading anchors in the repo's markdown.
# External links are skipped; nothing is fetched. Exits 1 on any broken link.
set -euo pipefail
export LC_ALL=C.UTF-8

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Markdown text without fenced code blocks.
prose() { awk '/^```/ { fenced = !fenced; next } !fenced' "$1"; }

# GitHub-style anchors for every heading in a file, one per line.
anchors() {
  prose "$1" | sed -nE 's/^#{1,6}[[:space:]]+(.+)$/\1/p' | sed -E 's/[[:space:]]*#*[[:space:]]*$//' |
    awk '{
      slug = tolower($0)
      gsub(/[^[:alnum:]_ -]/, "", slug)
      gsub(/ /, "-", slug)
      print (seen[slug]++ ? slug "-" (seen[slug] - 1) : slug)
    }'
}

urldecode() { printf '%b' "${1//%/\\x}"; }

declare -A ANCHOR_CACHE=()
checked=0
errors=0
while IFS= read -r -d '' file; do
  dir="$(dirname "$file")"
  rel="${file#"$ROOT"/}"
  while IFS= read -r link; do
    dest="${link#*](}"
    dest="${dest%)}"
    dest="${dest#<}"
    dest="${dest%>}"
    # Skip anything with a scheme (https:, mailto:) or a host (//example.com).
    [[ "$dest" =~ ^[A-Za-z][A-Za-z0-9+.-]*: || "$dest" == //* ]] && continue
    path="${dest%%#*}"
    fragment=""
    [[ "$dest" == *"#"* ]] && fragment="$(urldecode "${dest#*#}")"
    path="$(urldecode "${path%%\?*}")"
    if [[ -n "$path" ]]; then target="$(realpath -m "${dir}/${path}")"; else target="$file"; fi
    checked=$((checked + 1))
    label="${rel}: ${dest}"
    if [[ "$target" != "$ROOT" && "$target" != "$ROOT"/* ]]; then
      echo "${label}: escapes the repository" >&2; errors=$((errors + 1))
    elif [[ ! -e "$target" ]]; then
      echo "${label}: missing target" >&2; errors=$((errors + 1))
    elif [[ -n "$fragment" && "$target" == *.md ]]; then
      [[ -v ANCHOR_CACHE[$target] ]] || ANCHOR_CACHE[$target]="$(anchors "$target")"
      if ! grep -qxF -- "$fragment" <<<"${ANCHOR_CACHE[$target]}"; then
        echo "${label}: missing heading" >&2; errors=$((errors + 1))
      fi
    fi
  done < <(prose "$file" | grep -oE '\[[^]]*\]\([^) ]+\)' || true)
done < <(find "$ROOT" -name '*.md' -not -path "$ROOT/.git/*" -print0 | sort -z)

echo "Checked ${checked} active-document local links; ${errors} errors."
(( errors == 0 ))
