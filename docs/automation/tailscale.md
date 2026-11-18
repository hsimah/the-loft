# Tailscale: off-LAN access

Phones and laptops reach space-needle's household apps over the tailnet, using the same `*.loft.hsimah.com` names and certificates as on the LAN. Nothing goes on the Cloudflare tunnel. Decision D9. **Proposed**; the current state below is from `tailscale status` on space-needle (2026-10-28).

## Current state

- The tailnet is used only for Viking management.
- space-needle: `100.69.51.18`, `tag:monitoring`, key expiry off, no routes advertised.
- Viking: `tag:viking`. Blanco: SSH to Viking.
- No phones; Georgia is not on the tailnet.

## Design

Policy: [policy.json](../../tailnet/policy.json), the admin console copy. It uses grants only, so everything not granted is denied.

| Piece | Proposed |
|---|---|
| Route | space-needle advertises `192.168.86.28/32`, its own LAN address, and nothing else. Traffic to it is delivered locally, so no IP forwarding or SNAT is involved. helarctos, Viking, the router and the rest of the LAN stay off the tailnet |
| DNS | Split DNS in the admin console: `loft.hsimah.com` → `192.168.86.28`. Mushr's dnsmasq binds that address (`listen-address` with `bind-interfaces`, [dnsmasq.conf](../../services/mushr/dnsmasq.conf)), so it answers tailnet queries unchanged |
| Grants | `autogroup:member` (every user's untagged devices) → `192.168.86.28/32` on `tcp:443`, `tcp:53`, `udp:53` (Caddy serves HTTP/1.1 and HTTP/2 only; add `udp:443` if HTTP/3 is turned on). No Forgejo SSH (`tcp:2222`; use HTTPS git off-LAN), no SSH to hosts, no helarctos, nothing on `tag:viking`. Autogroups keep logins out of the repo, and Georgia is covered when she joins |
| Login | Passkey or hardware MFA on each person's identity-provider account. Whoever holds the login can enrol devices |
| Tailnet Lock | On. Blanco and fjord hold the trusted signing keys; fjord is on the tailnet only for that (`tag:signer`, no grants). Disablement secrets are in the password manager, with a printed copy in the safe. A new node stays locked out until it is signed |
| Devices | Phones keep Tailscale always on (Android always-on VPN, iOS VPN On Demand) so ntfy and the web apps reach home without toggling. Laptops connect when away. Device keys keep the default expiry; tagged servers have none |
| Viking | Unchanged. Its [input firewall](../../hosts/viking/hardening/firewall-input.nft) admits only Blanco SSH and space-needle monitoring on `tailscale0` |

[test-platform.sh](../../tests/test-platform.sh) asserts that only the two existing grants reach `tag:viking`, that every other grant targets only `192.168.86.28/32` on the ports above, and that `tag:signer` appears in no grant.

At home, phones with Tailscale on still reach `192.168.86.28` through the tailnet (a direct LAN path). If space-needle's `tailscaled` is down, they lose the loft names until Tailscale is switched off on the phone.

## Signing new nodes

With Tailnet Lock on, every later enrolment (helarctos, Georgia's devices, a Viking re-enrol, a replacement phone) must be signed from Blanco or fjord:

```bash
sudo tailscale lock status    # the new node is listed as locked out, with its nodekey
sudo tailscale lock sign nodekey:<key>
```

## Rollout: Hamish

Devices: iPhone and Blanco (already enrolled).

1. **Login**: confirm a passkey or hardware MFA on the login the tailnet uses.
2. **Policy**: diff the admin console policy against [policy.json](../../tailnet/policy.json), paste it in and save.
3. **Route**: on space-needle, `sudo tailscale set --advertise-routes=192.168.86.28/32`. Use `set`, not `up`: `up` without the existing flags drops `--advertise-tags`. Approve the route in the admin console (Machines → space-needle → Edit route settings).
4. **DNS**: admin console → DNS → Add nameserver → Custom, `192.168.86.28`, restricted to `loft.hsimah.com`.
5. **fjord**: install Tailscale, then `sudo tailscale up --advertise-tags=tag:signer`. Disable key expiry in the admin console.
6. **iPhone**: install, sign in, turn on VPN On Demand.
7. **Tailnet Lock**, after every node above is enrolled, so that init signs them all:
   - On Blanco and on fjord, run `sudo tailscale lock status` and note each node's `tlpub:` key.
   - On Blanco, run `sudo tailscale lock init --gen-disablements 3 --confirm tlpub:<blanco> tlpub:<fjord>`.
   - Store the printed disablement secrets in the password manager; print a copy for the safe.
   - Check that `sudo tailscale lock status` lists both trusted keys and no locked-out nodes.
8. **Check** from the iPhone on mobile data: `https://sputnik.loft.hsimah.com` loads with a valid certificate; `http://192.168.86.21:8080` (helarctos) and Viking do not answer. From Blanco, SSH to Viking still works.

## Rollout: Georgia

1. Invite her as a tailnet user; she sets up a passkey or MFA on her login.
2. Install and sign in on her phone and laptop; set always-on on the phone.
3. [Sign](#signing-new-nodes) each device from Blanco or fjord.
4. Run the same check from her phone.

## Then

- helarctos: enrol with its own tag, [sign it](#signing-new-nodes), grant space-needle (`tag:monitoring`) → helarctos `tcp:8080`, and move llama-swap's consumers to its tailnet address ([maintenance](../../plans/maintenance.md), Model traffic). Consumers on helarctos itself, such as the Kennl runner, must still reach it.
- ntfy on iOS: instant delivery from a self-hosted server goes through ntfy.sh's upstream relay (message ID only, unverified). Check when ntfy is built.

## Open questions

- Does the free Personal plan's user limit cover two users?
- Does either phone run a work VPN? Phones run one VPN at a time, so always-on Tailscale would conflict.
