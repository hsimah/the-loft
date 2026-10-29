# Tailscale: off-LAN access

Phones and laptops reach space-needle's household apps over the tailnet, using the same `*.loft.hsimah.com` names and certificates as on the LAN. Nothing goes on the Cloudflare tunnel. Decision D9. **Proposed**; the current state below is from `tailscale status` on space-needle (2026-10-28).

## Current state

- The tailnet is used only for Viking management. Policy copy: [tailscale-policy.json](../../hosts/viking/hardening/tailscale-policy.json), grants only, so everything else is denied.
- space-needle: `100.69.51.18`, `tag:monitoring`, key expiry off, no routes advertised.
- Viking: `tag:viking`. Blanco: SSH to Viking.
- No phones; Georgia is not on the tailnet.

## Design

| Piece | Proposed |
|---|---|
| Route | space-needle advertises `192.168.86.28/32`, its own LAN address, and nothing else. Traffic to it is delivered locally, so no IP forwarding or SNAT is involved. helarctos, Viking, the router and the rest of the LAN stay off the tailnet |
| DNS | Split DNS in the admin console: `loft.hsimah.com` → `192.168.86.28`. Mushr's dnsmasq binds that address (`listen-address` with `bind-interfaces`, [dnsmasq.conf](../../services/mushr/dnsmasq.conf)), so it answers tailnet queries unchanged |
| Users | Georgia invited as a second tailnet user. `group:household` holds both logins |
| Grants | `group:household` → `192.168.86.28/32` on `tcp:443`, `udp:443` (HTTP/3), `tcp:53`, `udp:53`. Hamish also gets `tcp:2222` (Forgejo SSH). No SSH to hosts, no helarctos, nothing on `tag:viking` |
| Devices | Phones keep Tailscale always on (Android always-on VPN, iOS VPN On Demand) so ntfy and the web apps reach home without toggling. Laptops connect when away. Device keys keep the default expiry; tagged servers have none |
| Viking | Unchanged. Its [input firewall](../../hosts/viking/hardening/firewall-input.nft) admits only Blanco SSH and space-needle monitoring on `tailscale0` |

Grants to add beside the existing two:

```json
"groups": {"group:household": ["<hamish-login>", "<georgia-login>"]},
"grants": [
  {"src": ["group:household"], "dst": ["192.168.86.28/32"], "ip": ["tcp:443", "udp:443", "tcp:53", "udp:53"]},
  {"src": ["<hamish-login>"], "dst": ["192.168.86.28/32"], "ip": ["tcp:2222"]}
]
```

With household grants the policy is no longer Viking's: move it out of `hosts/viking/hardening/` to a fleet-level path when applying. [test-platform.sh](../../tests/test-platform.sh) asserts the exact current policy; change it to assert that the Viking grants are exactly the two above, that no grant from a user or group reaches `tag:viking`, and that household grants target only `192.168.86.28/32`.

At home, phones with Tailscale on still reach `192.168.86.28` through the tailnet (a direct LAN path). If space-needle's `tailscaled` is down, they lose the loft names until Tailscale is switched off on the phone.

## Rollout

1. **Policy**: diff the admin console policy against the repo copy, add the group and grants, save, and commit the same file.
2. **Route**: on space-needle, `sudo tailscale set --advertise-routes=192.168.86.28/32`. Use `set`, not `up`: `up` without the existing flags drops `--advertise-tags`. Approve the route in the admin console (Machines → space-needle → Edit route settings).
3. **DNS**: admin console → DNS → Add nameserver → Custom, `192.168.86.28`, restricted to `loft.hsimah.com`.
4. **Devices**: invite Georgia; install and sign in on both phones and laptops; set always-on on the phones.
5. **Check** from a phone on mobile data: `https://sputnik.loft.hsimah.com` loads with a valid certificate; `helarctos:8080` and Viking do not answer.

## Then

- helarctos: enrol with its own tag, grant space-needle (`tag:monitoring`) → helarctos `tcp:8080`, and move llama-swap's consumers to its tailnet address ([maintenance](../../plans/maintenance.md), Model traffic). Consumers on helarctos itself, such as the Kennl runner, must still reach it.
- Replace the "LAN only until Tailscale" notes in the Mercurius, Janus and documents pages once phones are on.
- ntfy on iOS: instant delivery from a self-hosted server goes through ntfy.sh's upstream relay (message ID only, unverified). Check when ntfy is built.

## Open questions

- Each person's Tailscale login (identity provider).
- Does the free Personal plan's user limit cover two users?
- Does either phone run a work VPN? Phones run one VPN at a time, so always-on Tailscale would conflict.
