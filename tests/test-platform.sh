#!/usr/bin/env bash
# test-platform.sh — check effective host isolation from `docker compose
# config` output, not fragments of override YAML. Needs the Compose CLI only.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/tests/lib/assert.sh"
require docker jq

# Compose versions differ on whether --no-env-resolution still checks env_file
# existence. Use copies with empty .env files, never live host secrets.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
(cd "$ROOT" && for f in services/*/docker-compose.yml hosts/*/overrides/*/docker-compose.override.yml; do
  mkdir -p "$WORK/$(dirname "$f")"
  cp "$f" "$WORK/$f"
  touch "$WORK/$(dirname "$f")/.env"
done)

cfg() { # host service [public] [profiles]; prints effective config JSON
  local args=(-f "services/$2/docker-compose.yml" -f "hosts/$1/overrides/$2/docker-compose.override.yml")
  [[ "${3:-}" == public ]] && args+=(--profile public)
  (cd "$WORK" && COMPOSE_PROFILES="${4:-}" docker compose "${args[@]}" config --no-env-resolution --format json \
    2> "$WORK/compose.err") || { cat "$WORK/compose.err" >&2; echo '{"error": "compose config failed"}'; }
}
q() { jq -c "$2" <<< "$1"; } # json filter

# ── fjord: no tunnel, no LAN proxy inheritance ───────────────────────────────
c="$(cfg fjord mushr)"
assert_eq "$(q "$c" '.services | keys')" '["mushr"]' "fjord runs only mushr"
assert_eq "$(q "$c" '.services.mushr | has("build") or has("extra_hosts")')" false "fjord mushr has no build or extra_hosts"
assert_eq "$(q "$c" '.networks | has("loft-proxy")')" false "fjord is not on loft-proxy"
assert_eq "$(q "$c" '.services.mushr.environment | keys')" '["XDG_CONFIG_HOME","XDG_DATA_HOME"]' "fjord mushr gets only XDG paths"
assert_eq "$(q "$c" '.services.mushr.ports[0].host_ip')" '"192.168.86.30"' "fjord binds its LAN address"
assert_eq "$(q "$c" '.services.mushr.volumes | length')" 1 "fjord mushr has one volume"

# ── viking: tunnel is opt-in and isolated ────────────────────────────────────
c="$(cfg viking mushr)"
assert_eq "$(q "$c" '.services | keys')" '["mushr"]' "viking has no tunnel by default"
c="$(cfg viking mushr public)"
assert_eq "$(q "$c" '.services | keys')" '["mushr","mushr-tunnel"]' "public profile adds the tunnel"
assert_eq "$(q "$c" '.services["mushr-tunnel"].networks | keys')" '["ingress"]' "tunnel is only on ingress"
assert_eq "$(q "$c" '.services["mushr-tunnel"] | has("ports") or has("environment")')" false "tunnel has no ports or environment"
assert_eq "$(q "$c" '.services.mushr.ports[0].host_ip')" '"127.0.0.1"' "viking mushr binds loopback"

# ── clog-prod network matches nginx's trusted proxy ──────────────────────────
assert_eq "$(q "$c" '.networks["clog-prod"] | [.internal, .name, .ipam.config[0].subnet]')" \
  '[true,"loft-clog-prod","172.30.93.0/29"]' "clog-prod is internal with the pinned subnet"
address="$(q "$c" '.services.mushr.networks["clog-prod"].ipv4_address' | tr -d '"')"
assert_contains "$(cat "${ROOT}/services/clog/nginx.conf")" "set_real_ip_from ${address};" "nginx trusts mushr's clog-prod address"
assert_eq "$(q "$c" '.services["mushr-tunnel"].networks | has("clog-prod")')" false "tunnel is not on clog-prod"

# ── pawst apps: separate, non-root, unpublished ──────────────────────────────
for spec in fjord:2 viking:1; do
  host="${spec%:*}"
  apps="$(cfg "$host" pawst)"
  proxy="$(cfg "$host" mushr)"
  assert_eq "$(q "$apps" '.services | length')" "${spec#*:}" "${host} runs one app per environment"
  assert_eq "$(q "$apps" '[.services[] | has("ports") or has("build")] | any')" false "${host} apps are unpublished and prebuilt"
  assert_eq "$(q "$apps" '[.services[] | .read_only == true and .user == "1003:1003"
    and (.cap_drop | index("ALL")) != null
    and (.security_opt | index("no-new-privileges:true")) != null
    and (.networks | length) == 1] | all')" true "${host} apps are read-only, non-root and unprivileged"
  assert_eq "$(q "$apps" '[.services[].networks | keys[0]] | length == (unique | length)')" true "${host} apps have separate networks"
  assert_eq "$(jq -c --argjson p "$proxy" '. as $a | [.services[].networks | keys[0]]
    | all(. as $n | $p.networks[$n].internal == true
      and $p.networks[$n].name == $a.networks[$n].name
      and $a.networks[$n].external == true)' <<< "$apps")" true "${host} app networks are internal and shared with mushr"
done

# ── viking monitoring never starts hub services ──────────────────────────────
for profiles in '' metrics hub hub,metrics,public; do
  c="$(cfg viking houstn '' "$profiles")"
  assert_eq "$(q "$c" '[(.services | keys), .services.glances.network_mode]')" '[["glances"],"host"]' \
    "viking houstn runs only host-network glances (profiles '${profiles}')"
done

# ── homepage reaches hosts by the right addresses ────────────────────────────
c="$(cfg space-needle houstn '' hub)"
hosts='.services.homepage.extra_hosts | map(split("=") | {key: .[0], value: (.[1:] | join("="))})'
assert_eq "$(q "$c" "${hosts} | length == (map(.key) | unique | length)")" true "homepage has no duplicate host mappings"
assert_eq "$(q "$c" "${hosts} | from_entries | [.viking, .fjord, .woodstock, .[\"host.docker.internal\"]]")" \
  '["100.119.43.53","192.168.86.30","192.168.86.37","host-gateway"]' "homepage uses Viking's tailnet and LAN addresses"

# ── tailnet policy grants only management and monitoring ─────────────────────
assert_eq "$(jq -c '.acls == [] and .hosts.blanco == "100.92.100.36" and .grants == [
  {src: ["blanco"], dst: ["tag:viking"], ip: ["tcp:22"]},
  {src: ["tag:monitoring"], dst: ["tag:viking"], ip: ["tcp:45876", "tcp:61208"]}]' \
  "${ROOT}/hosts/viking/hardening/tailscale-policy.json")" true "tailnet policy grants only SSH and monitoring"

# ── Caddy's file capability exception is narrow ──────────────────────────────
# Commas in unquoted YAML flow lists split mount options into separate mounts:
# Compose config accepts them, Docker rejects them. Hence the exact tmpfs.
TMPFS='["/tmp:uid=1003,gid=1003,mode=1770"]'
for host in fjord viking; do
  c="$(cfg "$host" mushr "$([[ $host == viking ]] && echo public)")"
  assert_eq "$(q "$c" '.services.mushr | [.user, .cap_add, .cap_drop, .read_only,
    (.security_opt | index("no-new-privileges:true") != null), .tmpfs]')" \
    "[\"1003:1003\",[\"NET_BIND_SERVICE\"],[\"ALL\"],true,true,${TMPFS}]" "${host} mushr adds only NET_BIND_SERVICE"
  assert_eq "$(q "$c" '[.services | to_entries[] | select(.key != "mushr") | .value.cap_add // [] | length == 0] | all')" true \
    "${host} other proxy services add no capabilities"
  assert_eq "$(q "$(cfg "$host" pawst)" "[.services[] | (.cap_add // [] | length == 0) and .tmpfs == ${TMPFS}] | all")" true \
    "${host} apps add no capabilities and use the exact tmpfs"
done

finish
