#!/usr/bin/env bash
# extract-release.sh — unpack a static-site release without links, special
# files or path traversal.
#
# Usage: extract-release.sh <archive.tar.gz> <destination>
#   - only regular files and directories; no absolute paths or ".." parts
#   - at most 100000 entries and 512 MiB uncompressed
#   - a single top-level wrapper directory is flattened
#   - the result must contain index.html
set -euo pipefail

ARCHIVE="$1"
DEST="$2"
MAX_BYTES=$((512 * 1024 * 1024))
MAX_ENTRIES=100000

die() { echo "$*" >&2; exit 1; }

# Check every entry before writing anything. GNU tar's verbose listing starts
# with the entry type: '-' file, 'd' directory, anything else is refused.
count=0
total=0
while read -r perms _owner size _date _time name; do
  [[ "${perms:0:1}" == - || "${perms:0:1}" == d ]] || die "Links and special files are not allowed"
  [[ "$name" != /* && "/${name}/" != */../* ]] || die "Archive path escapes destination"
  count=$((count + 1))
  total=$((total + size))
  (( count <= MAX_ENTRIES && total <= MAX_BYTES )) || die "Static release exceeds extraction limits"
done < <(tar -tvzf "$ARCHIVE" --numeric-owner --quoting-style=escape)

mkdir -p "$DEST"
tar -xzf "$ARCHIVE" -C "$DEST" --no-same-owner --no-same-permissions

# Flatten a single wrapper directory (e.g. site/index.html → index.html).
shopt -s dotglob nullglob
entries=("$DEST"/*)
if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" && ! -L "${entries[0]}" ]]; then
  wrapper="$(mktemp -d "${DEST}/.wrapper.XXXXXX")"
  rmdir "$wrapper"
  mv "${entries[0]}" "$wrapper"
  children=("$wrapper"/*)
  (( ${#children[@]} == 0 )) || mv "${children[@]}" "$DEST"/
  rmdir "$wrapper"
fi

[[ -f "${DEST}/index.html" && ! -L "${DEST}/index.html" ]] || die "Static release must contain index.html"
