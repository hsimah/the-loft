# viking

Production web host, currently a Raspberry Pi 3 B+ (arm64, 1 GB, Debian 13). The hardware is replaceable; the role is not. [host.conf](../../hosts/viking/host.conf) runs Mushr (with the `public` tunnel profile), [Pawst](../services/pawst.md), [Clog](../services/clog.md), Snoot and Houstn (Glances only). Recovery: [Viking restore](../operations/viking-restore.md).

Mutating `setup.sh`/`loft-ctl` runs require `/etc/loft/dmz-ready`, an operator attestation that the network boundary below is in place. Setup removes littledog from the Docker group here.

## Network

- Nest Wifi Pro guest network `Loft DMZ`: Viking gets `192.168.87.21/24` (DHCP lease), gateway/DNS `192.168.87.1`. NetworkManager on `wlan0`; the old trusted Wi-Fi profile is deleted and cloud-init is disabled.
- Tailscale for management only: Blanco `100.92.100.36` → Viking `100.119.43.53` TCP 22; space-needle `100.69.51.18` → Viking TCP 45876 (Beszel) and 61208 (Glances). Viking can initiate nothing on the tailnet.
- Public traffic: Cloudflare tunnel `viking-prod` → `mushr:8080` → apps. No router port forwards.
- Host firewall: nftables, default drop on input/output/forward. Egress allows guest DNS/DHCP, public HTTPS/NTP, Tailscale, and Cloudflare TCP/UDP 7844 from Docker. Private/LAN destinations are dropped. Host output allows TCP 8080 to `br-*` so `curl 127.0.0.1:8080` works through docker-proxy.
- Security updates via unattended-upgrades; no automatic reboots.

The tracked files and change procedure are in the [hardening baseline](../../hosts/viking/hardening/README.md). This is guest isolation plus host filtering, **not** a router-enforced VLAN DMZ; the stronger target policy is in the [application platform](../operations/application-platform.md#network-boundary).

Snoot and Glances are privileged host-monitoring exceptions (host network, Docker socket). Keep them away from public app containers. Homepage reaches `http://viking:61208` through a space-needle host mapping to the Tailscale IP.

## Constraints

- Docker memory limits are **not enforced**: the boot line has `cgroup_disable=memory`.
- Space-needle dnsmasq still has a stale `viking → 192.168.86.26`; use the Tailscale IP.
- `/var/backups/loft/viking-hardening-*.tar.gz` are local root-only copies of the hardening config, not full backups.
