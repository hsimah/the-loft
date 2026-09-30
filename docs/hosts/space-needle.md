# space-needle

Minisforum MS-01, x86_64, Ubuntu 24.04, wired LAN `192.168.86.28`. Primary server. [host.conf](../../hosts/space-needle/host.conf) owns services, storage directories and health URLs. Runs Howlr `server`, Houstn `hub,metrics`, Sputnik `engine,chat,agent`, Mushr, Pawpcorn, Pupyrus, Stellarr and Snoot.

## Storage and networking

`/mammoth` is XFS on `/dev/sda1` (confirm the device on new hardware; setup mounts but never formats). Media and model weights live there; app state lives under `/opt`.

[Mushr](../services/mushr.md) provides LAN DNS on `192.168.86.28` plus proxy/tunnel ingress. Bridge apps join `loft-proxy`; Plex, Music Assistant, Glances, Snoot and dnsmasq use host networking. Only Transmission and slskd share the VPN container's namespace.

[daemon.json](../../daemon.json) sets public upstream DNS for containers. Containers needing loft names set `dns: [192.168.86.28]` explicitly.

## Operations

```bash
cd /srv/the-loft
sudo bash setup.sh
loft-ctl health
loft-ctl update <service>
```
