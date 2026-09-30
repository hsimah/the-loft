#!/usr/bin/env bash
# stage-release.sh — verify a Clog archive and stage it as an immutable release
# directory named after its SHA-256. Never touches live data or services.
#
# Usage: stage-release.sh <archive.tar.gz> <sha256> [--releases DIR] [--reuse]
#   --releases  where releases live (default /opt/clog/releases)
#   --reuse     accept an existing release only if it matches the archive exactly
# Prints the release directory on success.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

[[ $# -ge 2 ]] || die "usage: $0 <archive> <sha256> [--releases DIR] [--reuse]"
ARCHIVE="$1"
DIGEST="$2"
shift 2
RELEASES=/opt/clog/releases
REUSE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --releases) RELEASES="$2"; shift 2 ;;
    --reuse) REUSE=true; shift ;;
    *) die "unknown option: $1" ;;
  esac
done

MAX_BYTES=$((256 * 1024 * 1024))
MAX_ENTRIES=30000
REQUIRED=(server/standalone/public/index.php server/standalone/cli.php
  server/vendor/autoload.php client/dist/.vite/manifest.json client/dist/assets/stylex.css)

[[ "$DIGEST" =~ ^[a-f0-9]{64}$ ]] || die "Expected a lowercase SHA-256 checksum"

# Work from a private copy so the verified bytes are the extracted bytes.
COPY="$(mktemp --suffix=.tar.gz)"
STAGE=""
trap 'rm -f "$COPY"; [[ -z "$STAGE" ]] || rm -rf "$STAGE"' EXIT
cp -- "$ARCHIVE" "$COPY"
[[ "$(sha256sum "$COPY" | cut -d ' ' -f 1)" == "$DIGEST" ]] || die "Archive checksum mismatch"

mkdir -p "$RELEASES"
TARGET="${RELEASES}/${DIGEST}"
if [[ -L "$TARGET" ]] || { [[ -e "$TARGET" ]] && ! $REUSE; }; then
  die "Release already exists; never overwrite a staged release"
fi

# Only regular files and directories under server/, client/ or hosting/.
declare -A seen=()
count=0
total=0
while read -r perms _owner size _date _time name; do
  path="${name%/}"
  path="${path#./}"
  if [[ "${perms:0:1}" != - && "${perms:0:1}" != d ]] || [[ -z "$path" || "$path" == /* ]] \
      || [[ "/${path}/" == */../* ]] || [[ ! "$path" =~ ^(server|client|hosting)(/|$) ]] \
      || [[ -n "${seen[$path]:-}" ]]; then
    die "Unsafe or duplicate archive entry: $name"
  fi
  seen[$path]=1
  count=$((count + 1))
  total=$((total + size))
done < <(tar -tvzf "$COPY" --numeric-owner --quoting-style=escape)
(( count <= MAX_ENTRIES && total <= MAX_BYTES )) || die "Archive exceeds the release size limit"

STAGE="$(mktemp -d "${RELEASES}/.stage-XXXXXX")"
tar -xzf "$COPY" -C "$STAGE" --no-same-owner --no-same-permissions
for file in "${REQUIRED[@]}"; do
  [[ -f "${STAGE}/${file}" ]] || die "Missing release file: $file"
done
find "$STAGE" -type f -exec chmod 0644 {} +
find "$STAGE" -type d -exec chmod 0755 {} +

# Directory list plus file checksums; refuses links and special files.
inventory() {
  local root="$1"
  if [[ -n "$(find "$root" -mindepth 1 ! -type f ! -type d -print -quit)" ]]; then
    die "Unexpected file in existing release: $root"
  fi
  (cd "$root" && find . -mindepth 1 -type d -printf 'dir %P\n' && find . -type f -exec sha256sum {} +) | LC_ALL=C sort
}

if [[ -e "$TARGET" ]]; then
  [[ -d "$TARGET" && "$(inventory "$TARGET")" == "$(inventory "$STAGE")" ]] \
    || die "Existing release differs from the verified archive"
else
  mv -T "$STAGE" "$TARGET"
  STAGE=""
fi
echo "$TARGET"
