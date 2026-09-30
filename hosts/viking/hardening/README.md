# Viking hardening baseline

Non-secret copies of the config installed on Viking. Setup does **not** apply them. The addresses and `wlan0` match the current host; adapt them for new hardware or networks. Never add Wi-Fi passwords, Tailscale node keys, SSH private keys or the tunnel token here.

| Source | Installed destination |
|---|---|
| `firewall*.nft` | `/etc/loft/` |
| `loft-firewall.service` | `/etc/systemd/system/loft-firewall.service` |
| `00-loft-hardening.conf` | `/etc/ssh/sshd_config.d/00-loft-hardening.conf` |
| `52loft-unattended-upgrades` | `/etc/apt/apt.conf.d/52loft-unattended-upgrades` |
| `tailscale-policy.json` | Tailscale admin console policy (review the whole existing policy first) |

The service loads only the `loft_host` and `loft_docker` tables in one transaction. They run after Docker/Tailscale chains, so Docker's managed rules must stay enabled. Never `flush ruleset` or enable the distro nftables service.

To change rules: diff against the installed files, back them up, `sudo nft --check --file ...`, schedule an automatic rollback, apply, test fresh SSH, monitoring and positive/negative container probes, then cancel the rollback. Update the Tailscale policy and input rule together when adding an admin.

The Cloudflare 7844 list is Cloudflare's 20 global IPv4 tunnel endpoints; recheck [their docs](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/tunnel-with-firewall/) when updating.
