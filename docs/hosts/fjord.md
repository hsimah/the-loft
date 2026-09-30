# fjord

Raspberry Pi 3 B+, arm64, `192.168.86.30`, no media volume. LAN-only dev/test. [host.conf](../../hosts/fjord/host.conf) runs Mushr (LAN proxy, no tunnel or DNS), Pawst dev/test, Snoot and Houstn metrics. **Not yet validated live.**

Conventions for environments, hostnames (`<app>.<dev|test>.fjord`) and promotion to Viking are in the [application platform](../operations/application-platform.md). Space-needle's DNS already resolves `*.fjord`; each name still needs a Caddy route. Never put Fjord behind a tunnel or port forward.

```bash
loft-ctl start mushr pawst
loft-ctl health
```

Pawst healthchecks fail until both sites are deployed to each environment; setup only creates empty roots.

Confirm which network manager the OS uses. The Wi-Fi watchdog defaults to `dhcpcd`; set `WIFI_DHCP_UNIT` in host.conf if it differs, then rerun setup.
