# fjord

Raspberry Pi 3 B+, arm64, LAN `192.168.86.30`. Its former Downstairs audio role moved to [Calavera](calavera.md). [host.conf](../../hosts/fjord/host.conf) now declares **Snoot and Houstn metrics only**; there is no Howlr environment to create.

Use the [Pi provisioning guide](../operations/raspberry-pi.md). Houstn uses `COMPOSE_PROFILES=metrics`. Obtain this system's Beszel token through [Snoot onboarding](../services/snoot.md); the hub public key is separate from that token.

```bash
loft-ctl health
loft-ctl update --all
```

The host has no media volume. `LITTLEDOG_EXTRA_GROUPS=audio` is a leftover from its prior role. Wi-Fi/watchdog checks are shared with [viking](viking.md#wi-fi-observations), but audio troubleshooting does not apply.

**Proposed:** repurpose Fjord for Georgia's cyberdeck. That software is not represented in this repo; this proposal is not deployed-state documentation.
