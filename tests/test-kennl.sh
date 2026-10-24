#!/usr/bin/env bash
# test-kennl.sh — keep CI jobs away from the host daemon, and helarctos's
# inference engine behind its key. Reads effective `docker compose config`
# output plus the runner and llama-swap configs. Needs the Compose CLI only.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/tests/lib/assert.sh"
require docker jq

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
for s in kennl sputnik; do
  mkdir -p "$WORK/services/$s"
  cp "${ROOT}/services/$s/docker-compose.yml" "$WORK/services/$s/"
  touch "$WORK/services/$s/.env"
done
# Kennl requires its variables to be set; the example sets them.
cp "${ROOT}/services/kennl/.env.example" "$WORK/services/kennl/.env"

cfg() { # service [profiles]; prints effective config JSON
  (cd "$WORK" && COMPOSE_PROFILES="${2:-}" docker compose -f "services/$1/docker-compose.yml" \
    config --no-env-resolution --format json 2> "$WORK/compose.err") \
    || { cat "$WORK/compose.err" >&2; echo '{"error": "compose config failed"}'; }
}
q() { jq -c "$2" <<< "$1"; } # json filter

# ── kennl: only kennl-dind touches a Docker daemon ───────────────────────────
c="$(cfg kennl)"
assert_eq "$(q "$c" '[.services[] | select(.privileged == true) | .container_name]')" '["kennl-dind"]' \
  "kennl-dind is the only privileged container"
assert_eq "$(q "$c" '[.services[].volumes[]? | select(.source // "" | test("docker.sock"))] | length')" 0 \
  "no kennl container mounts a Docker socket"
assert_eq "$(q "$c" '.services.runner.environment.DOCKER_HOST')" '"tcp://dind:2376"' \
  "the runner talks to kennl-dind over TLS"
assert_eq "$(q "$c" '[.services.runner.volumes[] | select(.target | startswith("/certs")) | .target]')" '["/certs/client"]' \
  "the runner holds only the dind client certificate"
assert_eq "$(q "$c" '.services.dind.environment.DOCKER_TLS_CERTDIR')" '"/certs"' \
  "kennl-dind serves its API over TLS only"
assert_eq "$(q "$c" '[.services[] | select(.user != null) | .container_name] | sort')" '["forgejo","forgejo-runner"]' \
  "forgejo and the runner run as a non-root user"

runner="${ROOT}/services/kennl/runner.yml"
assert_eq "$(sed -nE 's/^  privileged: (.*)$/\1/p' "$runner")" false "job containers are unprivileged"
assert_eq "$(sed -nE 's/^  docker_host: (.*)$/\1/p' "$runner")" '"-"' "job containers get no Docker socket"
assert_eq "$(sed -nE 's/^  valid_volumes: (.*)$/\1/p' "$runner")" '[]' "job containers may mount no volumes"

# ── sputnik gpu: llama-swap is LAN-reachable, so it must demand a key ────────
c="$(cfg sputnik gpu)"
assert_eq "$(q "$c" '.services | keys')" '["llama-swap"]' "the gpu profile runs only llama-swap"
assert_eq "$(q "$c" '.services["llama-swap"].cap_drop')" '["ALL"]' "llama-swap drops all capabilities"
swap="${ROOT}/services/sputnik/llama-swap.yaml"
assert_eq "$(sed -n '/^apiKeys:/{n;p}' "$swap")" '  - "${env.LLAMA_SWAP_API_KEY}"' \
  "llama-swap requires LLAMA_SWAP_API_KEY"

finish
