# fjord

Fjord is the LAN-only application development/test role. Current hardware is a
Raspberry Pi 3 B+, arm64, at `192.168.86.30`; it has no media volume. Its former
Downstairs audio role moved to [Calavera](calavera.md). The previous cyberdeck
proposal is superseded by this role; live provisioning still requires operator
verification.

[host.conf](../../hosts/fjord/host.conf) selects Mushr, Pawst dev/test, Snoot and
Houstn metrics. Follow the [application platform runbook](../operations/application-platform.md)
for the isolated Compose networks, internal hostnames, adding applications and
promoting the same GitHub artifact to Viking. No Cloudflare connector or public
ingress belongs on Fjord.

Use the [Pi provisioning guide](../operations/raspberry-pi.md), Houstn's
`COMPOSE_PROFILES=metrics` and [Snoot onboarding](../services/snoot.md) for the
existing metrics services. Deploy both sites to each environment before expecting
Pawst healthchecks to pass; setup creates empty document roots only.

```bash
loft-ctl start mushr pawst
loft-ctl health
```

The Mushr override needs no Cloudflare credentials or DNS server. Existing LAN
DNS resolves `*.fjord`; each route must also be explicitly added to Caddy.
Wi-Fi/watchdog observations remain in [Viking's retained notes](viking.md#wi-fi-observations).
