#!/usr/bin/env bash
# test-caddy.sh — structural checks on the fleet's Caddy configuration.
# Pure text analysis: no Docker daemon, no network, no Caddy binary. The
# syntax check that needs the xcaddy-built image runs separately in CI.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

ok()  { printf 'ok     %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf 'FAIL   %s\n     %s\n' "$1" "$2" >&2; FAIL=$((FAIL + 1)); }

# Fleet host names double as internal TLDs (foo.space-needle, bar.fjord).
# Anything under one of those is LAN-only and never reaches Cloudflare.
internal_tlds() { ls "${ROOT}/hosts"; }

is_internal() { # fqdn
  local fqdn="$1" tld
  tld="${fqdn##*.}"
  internal_tlds | grep -qx "$tld"
}

# Site addresses: column-zero lines opening a block, minus snippet definitions.
site_addresses() { # caddyfile
  grep -hE '^[^[:space:]#}].*\{[[:space:]]*$' "$1" \
    | sed -E 's/[[:space:]]*\{[[:space:]]*$//; s#^https?://##; s/:[0-9]+$//' \
    | grep -v '^(' || true
}

# Hostnames matched inside a site block, used by the DMZ hosts' single
# :8080 listener instead of separate site addresses.
host_matchers() { # caddyfile
  sed -nE 's/^[[:space:]]*@[A-Za-z0-9_]+[[:space:]]+host[[:space:]]+(.+)$/\1/p' "$1" \
    | tr ' ' '\n' | grep -v '^$' || true
}

all_caddyfiles() {
  printf '%s\n' "${ROOT}/services/mushr/Caddyfile"
  find "${ROOT}/hosts" -path '*/overrides/mushr/Caddyfile' | sort
}

# ── Declared public hostnames ────────────────────────────────────────────────
# host.conf declares INTENT; the tunnel's real list lives in Cloudflare. What
# the repository can enforce is that whatever it claims to publish is
# publishable, routed, and resolved locally — and that nothing publishable
# appears without being declared.
loft_domain=$(sed -nE 's/^LOFT_DOMAIN=(.+)$/\1/p' "${ROOT}/services/mushr/.env.example")
[[ -n "$loft_domain" ]] || loft_domain="loft.hsimah.com"

mushr_hosts() { ls "${ROOT}/hosts"; }

caddyfile_for() { # host
  if [[ "$1" == "space-needle" ]]; then
    echo "${ROOT}/services/mushr/Caddyfile"
  else
    echo "${ROOT}/hosts/$1/overrides/mushr/Caddyfile"
  fi
}

declared_for() { # host — PUBLIC_HOSTNAMES from that host.conf, one per line
  local conf="${ROOT}/hosts/$1/host.conf"
  [[ -f "$conf" ]] || return 0
  ( set +u
    # shellcheck disable=SC1090
    source "$conf" >/dev/null 2>&1
    [[ -v PUBLIC_HOSTNAMES ]] || exit 0
    printf '%s\n' "${PUBLIC_HOSTNAMES[@]}" ) | grep -v '^$' || true
}

# A hostname is "publishable-looking" if it is a literal FQDN under a real
# domain: not a {$LOFT_DOMAIN} template, not a wildcard, not under a fleet
# host name used as an internal TLD.
publishable_names() { # caddyfile
  { site_addresses "$1"; host_matchers "$1"; } | while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    [[ "$name" == *'{$'* ]] && continue
    [[ "$name" == '*'* ]] && continue
    [[ "$name" != *.* ]] && continue
    is_internal "$name" && continue
    printf '%s\n' "$name"
  done | sort -u
}

labels_of() { tr '.' '\n' <<< "$1" | grep -c .; }

# Rule 1: a declared name must be at most one label below its registrable
# domain, and must not be a loft name. Cloudflare's free Universal SSL covers
# example.com and *.example.com only; anything deeper fails at the edge.
bad_depth=""
while IFS= read -r host; do
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if [[ "$name" == *".${loft_domain}" || "$name" == "$loft_domain" ]]; then
      bad_depth+="${name} (${host}) is a loft name — LAN-only, cannot be published"$'\n'
    elif (( $(labels_of "$name") > 3 )); then
      bad_depth+="${name} (${host}) is $(labels_of "$name") labels deep"$'\n'
    fi
  done < <(declared_for "$host")
done < <(mushr_hosts)

if [[ -z "$bad_depth" ]]; then
  ok "every declared public hostname is first-level"
else
  bad "every declared public hostname is first-level" \
      "free Universal SSL cannot cover these:"$'\n'"${bad_depth}"
fi

# Rule 2: a declared name with no route 502s; a routed public name that is
# not declared is exposure nobody wrote down.
undeclared=""
unrouted=""
while IFS= read -r host; do
  cf=$(caddyfile_for "$host")
  [[ -f "$cf" ]] || continue
  decl=$(declared_for "$host")
  routed=$(publishable_names "$cf")
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    grep -qxF "$name" <<< "$decl" || undeclared+="${name} (${host})"$'\n'
  done <<< "$routed"
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    grep -qxF "$name" <<< "$routed" || unrouted+="${name} (${host})"$'\n'
  done <<< "$decl"
done < <(mushr_hosts)

if [[ -z "$undeclared" ]]; then
  ok "no Caddyfile serves a public hostname that host.conf does not declare"
else
  bad "no Caddyfile serves a public hostname that host.conf does not declare" \
      "add to PUBLIC_HOSTNAMES, or use a {\$LOFT_DOMAIN} name if it is LAN-only:"$'\n'"${undeclared}"
fi

if [[ -z "$unrouted" ]]; then
  ok "every declared public hostname has a Caddy route"
else
  bad "every declared public hostname has a Caddy route" \
      "declared but no site block or host matcher:"$'\n'"${unrouted}"
fi

# Rule 3: without a local DNS answer, a LAN client resolves the public name
# through Cloudflare and hairpins back in, so the tunnel's request-body cap
# applies to uploads from inside the house too.
dnsmasq="${ROOT}/services/mushr/dnsmasq.conf"
nolocal=""
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  grep -qE "^address=/${name//./\\.}/" "$dnsmasq" || nolocal+="${name}"$'\n'
done < <(declared_for space-needle)

if [[ -z "$nolocal" ]]; then
  ok "space-needle's public hostnames resolve locally via dnsmasq"
else
  bad "space-needle's public hostnames resolve locally via dnsmasq" \
      "missing address= entry, so LAN clients hairpin through Cloudflare:"$'\n'"${nolocal}"
fi

# ── Rule: every hostname space-needle health-checks must have a route, or
# the probe fails for a reason that has nothing to do with the service.
conf="${ROOT}/hosts/space-needle/host.conf"
caddy="${ROOT}/services/mushr/Caddyfile"

routes=$(site_addresses "$caddy" | sed "s/{\$LOFT_DOMAIN}/${loft_domain}/" | sort -u)
missing=""
while IFS= read -r host; do
  [[ -n "$host" ]] || continue
  grep -qxF "$host" <<< "$routes" || missing+="${host}"$'\n'
done < <(grep -oE '\[[^]]+:(lan|ssl)\]="https?://[^"]+"' "$conf" \
         | sed -E 's#.*https?://##; s#/.*##; s/"//g' | sort -u)

if [[ -z "$missing" ]]; then
  ok "every space-needle health URL has a matching Caddy route"
else
  bad "every space-needle health URL has a matching Caddy route" \
      "no site block serves:"$'\n'"${missing}"
fi

# ── Rule: the public name and the LAN name must reach the same upstream.
# Splitting them is how a service ends up working at home and 502ing away
# from it, or vice versa, with nothing in the config looking wrong.
upstream_for() { # exact site address as written in the Caddyfile
  awk -v want="$1" '
    index($0, want) == 1 {
      rest = substr($0, length(want) + 1)
      if (rest ~ /^[[:space:]]*\{[[:space:]]*$/) { inblock = 1 }
      next
    }
    inblock && $1 == "reverse_proxy" { print $2; inblock = 0 }
    inblock && /^\}/ { inblock = 0 }
  ' "$caddy" | head -1
}
pub=$(upstream_for 'hubbl.hsimah.com')
lan=$(upstream_for 'http://hubbl.space-needle:80')
lft=$(upstream_for 'hubbl.{$LOFT_DOMAIN}')
if [[ -n "$pub" && "$pub" == "$lan" && "$pub" == "$lft" ]]; then
  ok "hubbl's public, loft and LAN routes share one upstream (${pub})"
else
  bad "hubbl's public, loft and LAN routes share one upstream" \
      "public='${pub}' loft='${lft}' lan='${lan}'"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
