#!/usr/bin/env bash
# test-mercurius-llm.sh — Mercurius's one route out must stay what the docs
# say: Paperless and paperless-gpt may reach llama-swap on helarctos:8080 and
# nothing else, and SilverBullet has no route out. Checks that the firewall, Compose, setup.sh and the bootstrap agree,
# that the container is on no public network, and that the model it names
# exists. No Docker daemon and no root; the rules are parsed in a throwaway
# network namespace when the kernel allows one.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/tests/lib/assert.sh"

NFT="${ROOT}/hosts/space-needle/mercurius-egress.nft"
UNIT="${ROOT}/hosts/space-needle/loft-mercurius-egress.service"
BOOT="${ROOT}/hosts/space-needle/bootstrap"
COMPOSE="${ROOT}/services/mercurius/docker-compose.yml"
nft="$(cat "$NFT")"
compose="$(cat "$COMPOSE")"
service() { sed -n "/^  $1:\$/,/^  [a-z-]*:\$/p" "$COMPOSE" | sed '$d' | grep -v '^\s*#'; } # one service block, comments dropped
gpt="$(service paperless-gpt)"
paperless="$(service paperless)"

# ── The rules ────────────────────────────────────────────────────────────────
if command -v nft > /dev/null && unshare -rn true 2> /dev/null; then
  unshare -rn nft --check --file "$NFT" 2> /dev/null && ok "the rules parse" || bad "the rules parse" "nft --check failed"
else
  printf 'skip   nft or an unprivileged network namespace is unavailable\n'
fi
accepts="$(grep -E '^\s+iifname "mercurius-llm" ip daddr .* accept$' <<< "$nft")"
assert_eq "$(wc -l <<< "$accepts")" 1 "one new-connection rule for the bridge"
assert_contains "$accepts" "ip daddr 192.168.86.21 tcp dport 8080 accept" "which allows helarctos:8080 only"
assert_eq "$(grep -c 'iifname "mercurius-llm" counter drop' <<< "$nft")" 2 "everything else from the bridge is dropped, forwarded or to this host"
assert_absent "$(grep -v '^\s*#' <<< "$nft")" "flush ruleset" "Docker's rules are left alone"
assert_contains "$nft" "destroy table inet loft_mercurius" "reloading replaces only this table"
assert_contains "$nft" "hook forward priority 10" "runs after Docker's chains"
assert_absent "$(grep -v '^\s*#' <<< "$nft")" "nfproto ipv6 accept" "no IPv6 accept"
assert_contains "$(cat "$UNIT")" "ExecStart=/usr/sbin/nft -f /etc/loft/mercurius-egress.nft" "the unit loads this file"
assert_contains "$(cat "$UNIT")" "Before=network-pre.target docker.service" "and loads before Docker starts containers"

# ── The container ────────────────────────────────────────────────────────────
assert_contains "$gpt" "profiles: [ocr]" "paperless-gpt is opt-in"
assert_eq "$(sed -n '/^    networks:/,/^    [a-z_]*:/p' <<< "$gpt" | grep -cE '^      - ')" 2 "on two networks"
assert_contains "$gpt" "- mercurius-llm" "the filtered bridge"
assert_contains "$gpt" "- default" "and the internal network"
assert_absent "$gpt" "loft-proxy" "never on the LAN proxy network"
assert_absent "$gpt" "mercurius-proxy" "nor Caddy's network"
ports="$(grep -E '^\s+- "[0-9.]+:[0-9]+:[0-9]+"' <<< "$gpt")"
assert_contains "$ports" '"127.0.0.1:' "its web page listens on loopback only"
assert_eq "$(grep -cE '^\s+- "[0-9]+:' <<< "$gpt")" 0 "and publishes nothing on the LAN"
assert_eq "$(grep -c 'source: /mercurius/gpt/' <<< "$gpt")" 3 "its state is on the vault"
assert_eq "$(grep -c 'create_host_path: false' <<< "$gpt")" 3 "and no bind creates its source"
assert_contains "$paperless" "- mercurius-llm" "Paperless joins the same filtered bridge"
assert_contains "$paperless" "- mercurius-proxy" "and keeps Caddy's internal network"
assert_absent "$paperless" "loft-proxy" "but is still not on the LAN proxy network"
assert_eq "$(grep -o 'helarctos:[0-9.]*' <<< "$paperless" | grep -c 192.168.86.21)" 1 "Paperless pins the same address"
assert_contains "$compose" "mercurius-llm:
    external: true" "the bridge is created by setup.sh"
sb="$(service silverbullet)"
assert_absent "$sb" "mercurius-llm" "SilverBullet is not on the model bridge"
assert_absent "$sb" "loft-proxy" "nor on the LAN proxy network"
assert_contains "$sb" "- mercurius-proxy" "Caddy reaches it on the internal proxy network"

# The address the firewall allows is the one the container is pinned to, and
# the one helarctos's docs and Kennl's firewall already use for llama-swap.
addr="$(grep -oE '"helarctos:[0-9.]+"' <<< "$gpt" | tr -d '"' | cut -d: -f2)"
assert_contains "$nft" "ip daddr ${addr} tcp dport" "firewall and extra_hosts name the same address"
assert_contains "$(cat "${ROOT}/hosts/helarctos/kennl-egress.nft")" "ct original ip daddr ${addr}" "which is llama-swap's address in Kennl's firewall"
assert_contains "$gpt" "OPENAI_BASE_URL: http://helarctos:8080/v1" "the container dials the allowed port"

# ── Models and keys ──────────────────────────────────────────────────────────
swap="$(cat "${ROOT}/services/sputnik/llama-swap.yaml")"
for var in VISION_LLM_MODEL LLM_MODEL; do
  model="$(sed -nE "s/^ +${var}: ([a-z0-9.-]+)\$/\1/p" <<< "$gpt")"
  assert_contains "$swap" "\"${model}\":" "${var} (${model}) is a model in llama-swap.yaml"
done
for var in PAPERLESS_AI_LLM_MODEL PAPERLESS_AI_LLM_EMBEDDING_MODEL; do
  model="$(sed -nE "s/^ +${var}: ([a-z0-9.-]+)\$/\1/p" <<< "$paperless")"
  assert_contains "$swap" "\"${model}\":" "${var} (${model}) is a model in llama-swap.yaml"
done
assert_contains "$paperless" "PAPERLESS_AI_LLM_ENDPOINT: http://helarctos:8080/v1" "Paperless dials the allowed port"
env="$(cat "${ROOT}/services/mercurius/.env.example")"
for var in GPT_PAPERLESS_TOKEN LLAMA_SWAP_API_KEY COMPOSE_PROFILES; do
  assert_contains "$env" "${var}=" ".env.example sets ${var}"
done
assert_contains "$gpt" 'OPENAI_API_KEY: ${LLAMA_SWAP_API_KEY:-}' "the key comes from .env, not the repo"

# ── Installation ─────────────────────────────────────────────────────────────
setup="$(cat "${ROOT}/setup.sh")"
assert_contains "$setup" "com.docker.network.bridge.name=mercurius-llm mercurius-llm" "setup.sh creates the bridge the firewall matches"
assert_contains "$(cat "$BOOT")" "mercurius-egress.nft" "the bootstrap installs the rules"
assert_contains "$(cat "$BOOT")" "loft-mercurius-egress.service" "and the unit"
assert_contains "$(cat "$BOOT")" "nft --check --file /etc/loft/mercurius-egress.nft" "and checks them before enabling"
assert_contains "$(cat "${ROOT}/control-plane/mercurius-vault.sh")" "gpt/prompts" "the vault script creates paperless-gpt's directories"

finish
