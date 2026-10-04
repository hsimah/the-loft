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

# ── Rule: a publicly served name must sit one label below a registrable
# domain. Cloudflare's free Universal SSL covers example.com and
# *.example.com only; *.sub.example.com needs paid Advanced Certificate
# Manager. A deeper name silently fails TLS at the edge.
#
# Only literal names are checkable. A name written as foo.{$LOFT_DOMAIN} is
# LAN-only by convention and carries a Caddy-issued certificate instead, so
# the depth limit does not apply to it.
violations=""
while IFS= read -r file; do
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    [[ "$name" == *'{$'* ]] && continue      # LAN, Caddy-issued cert
    [[ "$name" == '*'* ]] && continue        # wildcard fallback
    [[ "$name" != *.* ]] && continue         # bare host, not an FQDN
    is_internal "$name" && continue          # *.space-needle, *.fjord, ...
    labels=$(tr '.' '\n' <<< "$name" | grep -c .)
    if (( labels > 3 )); then
      violations+="${name} (${file##*/the-loft/}, ${labels} labels)"$'\n'
    fi
  done < <( { site_addresses "$file"; host_matchers "$file"; } )
done < <(all_caddyfiles)

if [[ -z "$violations" ]]; then
  ok "every public hostname is at most one label below its domain"
else
  bad "every public hostname is at most one label below its domain" \
      "Cloudflare free Universal SSL cannot cover these:"$'\n'"${violations}"
fi

# ── Rule: every hostname space-needle health-checks must have a route, or
# the probe fails for a reason that has nothing to do with the service.
conf="${ROOT}/hosts/space-needle/host.conf"
caddy="${ROOT}/services/mushr/Caddyfile"
loft_domain=$(sed -nE 's/^LOFT_DOMAIN=(.+)$/\1/p' "${ROOT}/services/mushr/.env.example")
[[ -n "$loft_domain" ]] || loft_domain="loft.hsimah.com"

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
