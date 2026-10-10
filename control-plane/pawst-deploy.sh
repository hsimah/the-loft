#!/usr/bin/env bash
# pawst-deploy.sh — deploy a Pawst site's latest (or given) GitHub release to
# Viking prod. GitHub's asset digest is the checksum; nothing is pinned in Git.
# Run through `loft-ctl deploy pawst`; see docs/services/pawst.md.
set -euo pipefail

CONTROL_PLANE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROD_ROOT="/opt/pawst/prod"
declare -A DOMAINS=([hblake]=hbla.ke [hsimah]=hsimah.com)

usage() {
  cat <<'EOF'
Usage: pawst-deploy.sh [--no-verify] <hblake|hsimah> [tag]

Deploy the site's latest GitHub release, or the given tag, to Viking prod.
  --no-verify  skip the local site check (restore runs it with Pawst stopped)
EOF
}

fail() { echo "ERROR: $*" >&2; exit 1; }

VERIFY=true
if [[ "${1:-}" == --no-verify ]]; then VERIFY=false; shift; fi
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  hblake|hsimah) ;;
  *) usage >&2; fail "Unknown site: ${1:-<none>}" ;;
esac
[[ $# -le 2 ]] || { usage >&2; fail "Too many arguments"; }
SITE="$1"
REQUESTED="${2:-}"
REPO="hsimah-services/${SITE}"

AUTH_HEADER=()
if TOKEN="$("${CONTROL_PLANE_DIR}/github-app-token.sh" 2>/dev/null)"; then
  AUTH_HEADER=(-H "Authorization: Bearer ${TOKEN}")
fi

if [[ -n "$REQUESTED" ]]; then
  RELEASE_PATH="tags/$(jq -rn --arg tag "$REQUESTED" '$tag | @uri')"
else
  RELEASE_PATH=latest
fi
RELEASE_JSON="$(curl -fsS "${AUTH_HEADER[@]}" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPO}/releases/${RELEASE_PATH}")" \
  || fail "Failed to query ${RELEASE_PATH} release for ${REPO}"

TAG="$(jq -r '.tag_name // empty' <<<"$RELEASE_JSON")"
[[ -n "$TAG" ]] || fail "No tag_name in release response for ${REPO}"
# deploy-pull.sh enforces the single-asset contract; this only reads its digest.
DIGEST="$(jq -r '[.assets[] | select(.name | endswith(".tar.gz"))]
  | if length == 1 then .[0].digest // "" else "" end' <<<"$RELEASE_JSON")"
[[ "$DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]] \
  || fail "Release ${TAG} needs exactly one .tar.gz asset with a sha256 digest"

echo "Deploying ${REPO} ${TAG}"
bash "${CONTROL_PLANE_DIR}/deploy-pull.sh" \
  "pawst-${SITE}" "$REPO" "${PROD_ROOT}/${SITE}" '' "$TAG" "${DIGEST#sha256:}"

if $VERIFY; then
  curl --noproxy '*' --fail --silent --show-error --max-time 10 -o /dev/null \
    -H "Host: ${DOMAINS[$SITE]}" http://127.0.0.1:8080/index.html \
    || fail "${DOMAINS[$SITE]} did not serve index.html after deploying ${TAG}"
  echo "${DOMAINS[$SITE]} serving ${TAG}"
fi
