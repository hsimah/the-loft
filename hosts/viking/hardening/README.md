# Viking hardening baseline

These are non-secret copies of the configuration installed and tested by the
operator on **2026-09-20**. They are not automatically applied by setup and do not
prove equivalent protection on another network. See the
[live hardening record](../../../docs/operations/viking-hardening.md) before use.

| Source | Installed destination |
|---|---|
| `firewall*.nft` | `/etc/loft/` |
| `loft-firewall.service` | `/etc/systemd/system/loft-firewall.service` |
| `00-loft-hardening.conf` | `/etc/ssh/sshd_config.d/00-loft-hardening.conf` |
| `52loft-unattended-upgrades` | `/etc/apt/apt.conf.d/52loft-unattended-upgrades` |
| `tailscale-policy.json` | Tailscale admin console access policy (review whole existing policy before replacement) |

The addresses and wlan0 match this deployment. Adapt them for replacement
hardware or a changed network; update the Tailscale policy and host input rule
together when adding the second administrator. Do not copy any Wi-Fi password,
Tailscale node keys, SSH private keys or Cloudflare token into this directory.

For a rule change: compare the installed files first, back them up, stage the
new file, run `sudo nft --check --file ...`, schedule an automatic rollback, apply,
test a fresh SSH connection/monitoring and positive/negative container probes,
then cancel rollback and update the persistent loader. Never use `flush ruleset`
or enable the distro nftables service with an unreviewed default configuration.
The dedicated service loads only loft_host and loft_docker in one transaction.

Cloudflare tunnel TCP/UDP 7844 is allowed to the 20 documented global IPv4
endpoints reviewed on 2026-09-20. Recheck Cloudflare's tunnel firewall documentation
when updating this list. The exception applies to bridges using public_egress;
Pawst has only an internal network. Host output also permits TCP 8080 to Docker
bridges for docker-proxy's loopback-origin connections; this is not a container
forwarding exception and is not limited to a particular process or container.
Public HTTPS, NTP and Tailscale UDP transport are documented egress exceptions;
this is not an application-aware Internet allowlist. Containers with an egress
bridge can reach public HTTPS; Pawst's internal-only network cannot.

The guest network does not expose configurable inter-VLAN rules. This tested
combination uses Nest guest isolation, restrictive host/container filtering and
Tailscale policy. It does not claim the full router policy from the long-term
DMZ design, nor protection from an attacker with root disabling host rules.
