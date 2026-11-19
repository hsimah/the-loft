# Tailscale: off-LAN access

Phones and laptops reach space-needle's household apps over the tailnet, using the same `*.loft.hsimah.com` names and certificates as on the LAN. Nothing goes on the Cloudflare tunnel. Decision D9. **Live for Hamish** (iPhone, Blanco), verified 2026-11-18; Georgia pending.

## Current state

- space-needle: `100.69.51.18`, `tag:monitoring`, key expiry off, advertises `192.168.86.28/32` (approved).
- Viking: `tag:viking`. fjord: `tag:signer`, key expiry off, `--accept-dns=false`.
- Users: Hamish (GitHub login, 2FA). Devices: Blanco, iPhone.
- Tailnet Lock enabled; trusted keys on Blanco and fjord.
- Split DNS `loft.hsimah.com` → `192.168.86.28` in the admin console.

## Design

Policy: [policy.json](../../tailnet/policy.json), the admin console copy. It uses grants only, so everything not granted is denied.

| Piece | Setting |
|---|---|
| Route | space-needle advertises `192.168.86.28/32`, its own LAN address, and nothing else. Traffic to it is delivered locally, so no IP forwarding or SNAT is involved. helarctos, Viking, the router and the rest of the LAN stay off the tailnet |
| DNS | Split DNS in the admin console: `loft.hsimah.com` → `192.168.86.28`. Mushr's dnsmasq binds that address (`listen-address` with `bind-interfaces`, [dnsmasq.conf](../../services/mushr/dnsmasq.conf)), so it answers tailnet queries unchanged |
| Grants | `autogroup:member` (every user's untagged devices) → `192.168.86.28/32` on `tcp:443`, `tcp:53`, `udp:53` (Caddy serves HTTP/1.1 and HTTP/2 only; add `udp:443` if HTTP/3 is turned on). No Forgejo SSH (`tcp:2222`; use HTTPS git off-LAN), no SSH to hosts, no helarctos, nothing on `tag:viking`. Autogroups keep logins out of the repo, and Georgia is covered when she joins |
| Login | Passkey or hardware MFA on each person's identity-provider account. Whoever holds the login can enrol devices |
| Tailnet Lock | On. Blanco and fjord hold the trusted signing keys; fjord is on the tailnet only for that (`tag:signer`, no grants). Disablement secrets are in the password manager, with a printed copy in the safe. A new node stays locked out until it is signed |
| Devices | Phones keep Tailscale on away from home so ntfy and the web apps reach home without toggling: iOS VPN On Demand on every network except the home Wi-Fi; Android always-on VPN. Laptops connect when away. Device keys keep the default expiry; tagged servers have none |
| Viking | Unchanged. Its [input firewall](../../hosts/viking/hardening/firewall-input.nft) admits only Blanco SSH and space-needle monitoring on `tailscale0` |

[test-platform.sh](../../tests/test-platform.sh) asserts that only the two existing grants reach `tag:viking`, that every other grant targets only `192.168.86.28/32` on the ports above, and that `tag:signer` appears in no grant.

At home, an iPhone drops Tailscale on the home Wi-Fi and uses Mushr DNS from DHCP directly. Android phones, with Tailscale on at home, still reach `192.168.86.28` through the tailnet (a direct LAN path); if space-needle's `tailscaled` is down, they lose the loft names until Tailscale is switched off.

## Signing new nodes

With Tailnet Lock on, every later enrolment (helarctos, Georgia's devices, a Viking re-enrol, a replacement phone) must be signed from Blanco or fjord:

```bash
sudo tailscale lock status    # the new node is listed as locked out, with its nodekey
sudo tailscale lock sign nodekey:<key>
```

Replacing a signer (for example, fjord's SD card fails): re-enrol it, sign it from the surviving signer, then on that signer run `sudo tailscale lock add tlpub:<new>` and `sudo tailscale lock remove tlpub:<old>`. If both signers are lost, use a disablement secret.

## Adding Georgia

1. Invite her as a tailnet user; she sets up a passkey or MFA on her login.
2. Install and sign in on her phone and laptop; set the phone up as in the Devices row.
3. [Sign](#signing-new-nodes) each device from Blanco or fjord.
4. Check from her phone on mobile data: `https://sputnik.loft.hsimah.com` loads with a valid certificate; `http://192.168.86.21:8080` (helarctos) and `http://100.119.43.53:61208` (Viking) do not answer.

## Then

- helarctos: enrol with its own tag, [sign it](#signing-new-nodes), grant space-needle (`tag:monitoring`) → helarctos `tcp:8080`, and move llama-swap's consumers to its tailnet address ([maintenance](../../plans/maintenance.md), Model traffic). Consumers on helarctos itself, such as the Kennl runner, must still reach it. Enrol LAN servers with `--accept-dns=false`, as fjord is, and never `--accept-routes`: on Linux it sends their traffic for `192.168.86.28` (Mushr DNS, Caddy) through the tailnet, where tagged servers have no grant, so it is silently dropped.
- ntfy on iOS: instant delivery from a self-hosted server goes through ntfy.sh's upstream relay (message ID only, unverified). Check when ntfy is built.

## Open questions

- Does the free Personal plan's user limit cover two users?
- Does Georgia's phone run a work VPN? Phones run one VPN at a time, so always-on Tailscale would conflict. (Hamish's does not.)
