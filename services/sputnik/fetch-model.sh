#!/usr/bin/env bash
# fetch-model.sh — download GGUF weights from Hugging Face for llama-swap.
#
# Resumable and checked: each file is fetched with curl -C - and verified
# against the SHA-256 Hugging Face publishes for it. Verified files are
# recorded in <dest>/SHA256SUMS and skipped on reruns, so an interrupted
# overnight download just needs running again.
#
# Usage: fetch-model.sh <hf-repo> <path-prefix> <dest-name>
#   fetch-model.sh ggml-org/gpt-oss-120b-GGUF gpt-oss-120b-MXFP4 gpt-oss-120b
# Writes to ${MODELS_DIR:-/den/sputnik/models}/<dest-name>/.
#   docs/services/sputnik.md#gpu-engine-on-helarctos
set -euo pipefail

if [[ $# -ne 3 ]]; then
  sed -n '9,11p' "$0" >&2
  exit 2
fi
repo="$1" prefix="$2" name="$3"
dest="${MODELS_DIR:-/den/sputnik/models}/${name}"
hf="https://huggingface.co"

# One line per file: sha256, size, path. Only .gguf files under the prefix.
listing="$(curl -fsS --retry 3 "${hf}/api/models/${repo}/tree/main?recursive=true")"
mapfile -t files < <(jq -r --arg p "$prefix" '.[]
  | select(.type == "file" and (.path | startswith($p)) and (.path | endswith(".gguf")))
  | "\(.lfs.oid) \(.size) \(.path)"' <<< "$listing")
if [[ ${#files[@]} -eq 0 ]]; then
  echo "No .gguf files under '${prefix}' in ${repo}" >&2
  exit 1
fi

mkdir -p "$dest"
touch "${dest}/SHA256SUMS"
total=0
for f in "${files[@]}"; do total=$(( total + $(cut -d' ' -f2 <<< "$f") )); done
echo "${repo} ${prefix}: ${#files[@]} file(s), $(( total / 1000000000 )) GB → ${dest}"

for f in "${files[@]}"; do
  read -r sha size path <<< "$f"
  file="${path##*/}"
  out="${dest}/${file}"
  if grep -qxF "${sha}  ${file}" "${dest}/SHA256SUMS"; then
    echo "ok       ${file} (verified earlier)"
    continue
  fi
  # A complete file makes the server answer 416 to a resume; just verify it.
  if [[ "$(stat -c %s "$out" 2>/dev/null || echo 0)" != "$size" ]]; then
    echo "fetch    ${file} ($(( size / 1000000000 )) GB)"
    curl -fL --retry 5 --retry-delay 10 -C - -o "$out" "${hf}/${repo}/resolve/main/${path}"
  fi
  echo "verify   ${file}"
  if [[ "$(sha256sum "$out" | cut -d' ' -f1)" != "$sha" ]]; then
    rm -f "$out"
    echo "SHA-256 mismatch for ${file}; deleted it, rerun to fetch again" >&2
    exit 1
  fi
  printf '%s  %s\n' "$sha" "$file" >> "${dest}/SHA256SUMS"
  echo "ok       ${file}"
done
echo "Done: ${dest}"
