# fjord

Fjord is a LAN-only host awaiting a new purpose, with monitoring retained. Hardware is a Raspberry Pi 3 B+,
arm64, with 1 GB RAM at `192.168.86.30`, with no dedicated data mount. The operator
reports it is back online with OS packages updated and fleet setup rerun
(2026-09-26). Its former Downstairs audio role moved to [Calavera](calavera.md).

[host.conf](../../hosts/fjord/host.conf) selects **Snoot and Houstn/Glances only**.
The [Houstn override](../../hosts/fjord/overrides/houstn/docker-compose.override.yml)
prevents stale profile settings from starting hub services. Howlr, Pawst and
Mushr must be explicitly stopped; manifest removal alone does not stop containers.
Old application overrides are retained as inactive reference configurations.

Agent development has moved to the proposed
[Ladygrey host](../../plans/ladygrey-development-runner.md), confirmed
as a Core i5 / 8 GB device. Fjord will not host agent checkouts, queue polling,
credentials or worker sessions. A new purpose will be chosen separately.
The [earlier runner guide](../operations/fjord-dev-runner.md#retire-old-fjord-workloads)
retains commands for retiring Fjord's old workloads; its runner setup sections
are a legacy prototype, not instructions to provision agents on Fjord.

```bash
loft-ctl start snoot houstn
loft-ctl health
```

Use the [Pi provisioning guide](../operations/raspberry-pi.md) and
[Snoot onboarding](../services/snoot.md) for maintenance and monitoring. Existing
LAN DNS resolves `*.fjord`, which does not mean a proxy or application is running.
No Cloudflare connector or public ingress belongs here. Wi-Fi/watchdog
observations remain in [Viking's notes](viking.md#wi-fi-observations).
The monitoring-only manifest stays in place while the next role is decided.
