#!/usr/bin/env bash
# deploy-pull.sh — deploy a pinned GitHub Release (or legacy latest) to a directory.
#
# Usage: deploy-pull.sh <name> <repo> <target_dir> [post_hook] [release_tag sha256]
#   name         — short identifier, used for state file & log prefix (e.g. pawst-hblake)
#   repo         — GitHub repo in "owner/repo" form (e.g. hsimah-services/hbla.ke)
#   target_dir   — directory to sync the release's tarball contents into
#   post_hook    — optional shell snippet run after a successful sync (cwd = target_dir)
#   release_tag  — optional explicit release, requires sha256; supports rollback
#   sha256       — expected lowercase archive digest for a pinned release
#
# Auth: if /etc/loft/deploy.env exposes GitHub App credentials, requests are
# authenticated and private repos work. Otherwise unauthenticated public access
# is attempted (rate-limited; fine for hourly polling of a public repo).
#
# State: /var/lib/loft/deploy/<name>.version — holds last-deployed tag.
# Release contract:
#   - Repo publishes a release with a single .tar.gz asset whose contents are
#     the deployable tree (no top-level wrapper directory required; both
#     wrapped and unwrapped tarballs handled).
set -euo pipefail

CONTROL_PLANE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="/var/lib/loft/deploy"

if [[ $# -lt 3 || $# -gt 6 ]]; then
  echo "Usage: $0 <name> <repo> <target_dir> [post_hook] [release_tag sha256]" >&2
  exit 1
fi

NAME="$1"
REPO="$2"
TARGET="$3"
POST_HOOK="${4:-}"
RELEASE_TAG="${5:-}"
EXPECTED_SHA256="${6:-}"
HOST_MANIFEST="${CONTROL_PLANE_DIR}/../hosts/$(hostname)/host.conf"
PRODUCTION=false
if [[ -f "$HOST_MANIFEST" ]]; then
  PRODUCTION="$(source "$HOST_MANIFEST"; printf '%s' "${PRODUCTION_ROLE:-false}")"
fi
if [[ "$PRODUCTION" == true && ( -z "$RELEASE_TAG" || -z "$EXPECTED_SHA256" ) ]]; then
  echo "Production deployments require an explicit tag and SHA256" >&2
  exit 1
fi
[[ "$NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || { echo "Invalid deploy name" >&2; exit 1; }
[[ "$REPO" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]] || { echo "Invalid repository" >&2; exit 1; }
if [[ -n "$RELEASE_TAG" || -n "$EXPECTED_SHA256" ]]; then
  [[ -n "$RELEASE_TAG" && "$EXPECTED_SHA256" =~ ^[a-f0-9]{64}$ ]] || {
    echo "Pinned deployments require a release tag and lowercase SHA256" >&2; exit 1;
  }
fi

LOG_PREFIX="[deploy:${NAME}]"
log() { echo "$(date -Is) ${LOG_PREFIX} $*"; }
fail() { log "ERROR: $*"; exit 1; }

mkdir -p "$STATE_DIR"
# Serialize cron/manual invocations before reading deployment state.
exec 9>"${STATE_DIR}/${NAME}.lock"
flock -n 9 || fail "Another deployment of ${NAME} is running"
STATE_FILE="${STATE_DIR}/${NAME}.version"
HASH_FILE="${STATE_DIR}/${NAME}.sha256"
LAST_TAG=""
[[ -f "$STATE_FILE" ]] && LAST_TAG="$(<"$STATE_FILE")"

# ── Auth (best-effort) ──────────────────────────────────────────────────────
AUTH_HEADER=()
if TOKEN="$("${CONTROL_PLANE_DIR}/github-app-token.sh" 2>/dev/null)"; then
  AUTH_HEADER=(-H "Authorization: Bearer ${TOKEN}")
fi

api() {
  curl -fsS "${AUTH_HEADER[@]}" -H "Accept: application/vnd.github+json" "$@"
}

# ── Fetch release metadata ──────────────────────────────────────────────────
RELEASE_PATH=latest
if [[ -n "$RELEASE_TAG" ]]; then
  RELEASE_PATH="tags/$(jq -rn --arg tag "$RELEASE_TAG" '$tag | @uri')"
fi
RELEASE_JSON="$(api "https://api.github.com/repos/${REPO}/releases/${RELEASE_PATH}")" \
  || fail "Failed to query release for ${REPO}"

TAG="$(printf '%s' "$RELEASE_JSON" | jq -r '.tag_name // empty')"
[[ -z "$TAG" ]] && fail "No tag_name in release response for ${REPO}"

[[ -z "$RELEASE_TAG" || "$TAG" == "$RELEASE_TAG" ]] || fail "Release tag mismatch"
LAST_SHA256=""
[[ -f "$HASH_FILE" ]] && LAST_SHA256="$(<"$HASH_FILE")"
# Recovery can re-fetch a recorded release under the same deployment lock.
if [[ "${LOFT_FORCE_DEPLOY:-0}" != 1 && "$TAG" == "$LAST_TAG" && ( -z "$EXPECTED_SHA256" || "$EXPECTED_SHA256" == "$LAST_SHA256" ) ]]; then
  log "Already at ${TAG}, nothing to do."
  exit 0
fi

ASSET_COUNT="$(printf '%s' "$RELEASE_JSON" | jq '[.assets[] | select(.name | endswith(".tar.gz"))] | length')"
[[ "$ASSET_COUNT" == 1 ]] || fail "Expected exactly one .tar.gz release asset"
ASSET_URL="$(printf '%s' "$RELEASE_JSON" \
  | jq -r '.assets[] | select(.name | endswith(".tar.gz")) | .url' \
  | head -1)"
[[ -z "$ASSET_URL" ]] && fail "No .tar.gz asset on release ${TAG} for ${REPO}"

log "New release ${TAG} (was: ${LAST_TAG:-none})"

# ── Download tarball ────────────────────────────────────────────────────────
TARBALL="$(mktemp --suffix=.tar.gz)"
trap 'rm -f "$TARBALL"' EXIT

curl -fsSL "${AUTH_HEADER[@]}" \
  -H "Accept: application/octet-stream" \
  -o "$TARBALL" \
  "$ASSET_URL" || fail "Failed to download asset"

ACTUAL_SHA256="$(sha256sum "$TARBALL" | cut -d ' ' -f 1)"
[[ -z "$EXPECTED_SHA256" || "$ACTUAL_SHA256" == "$EXPECTED_SHA256" ]] || fail "Release checksum mismatch"

# ── Stage and sync ──────────────────────────────────────────────────────────
# TARGET is synced in place (never renamed/replaced): it may be bind-mounted
# into a running container, and bind mounts track the inode — replacing the
# directory would leave the container serving the deleted old tree.
PARENT="$(dirname "$TARGET")"
BASENAME="$(basename "$TARGET")"
mkdir -p "$PARENT"

STAGING="$(mktemp -d "${PARENT}/.${BASENAME}.deploy.XXXXXX")"
trap 'rm -f "$TARBALL"; rm -rf "$STAGING"' EXIT
python3 "${CONTROL_PLANE_DIR}/extract-release.py" "$TARBALL" "$STAGING" || fail "Unsafe or invalid release archive"

chown -R littledog:pack-member "$STAGING" 2>/dev/null || true
chmod -R u=rwX,go=rX "$STAGING"

mkdir -p "$TARGET"
rsync -a --delete "$STAGING"/ "$TARGET"/ || fail "rsync into ${TARGET} failed"

echo "$ACTUAL_SHA256" > "$HASH_FILE"
echo "$TAG" > "$STATE_FILE"
log "Deployed ${TAG} to ${TARGET}"

# ── Post-deploy hook ────────────────────────────────────────────────────────
if [[ -n "$POST_HOOK" ]]; then
  log "Running post-deploy hook"
  ( cd "$TARGET" && bash -c "$POST_HOOK" ) || log "WARNING: post-deploy hook exited non-zero"
fi
