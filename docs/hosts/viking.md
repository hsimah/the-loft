# viking

Viking is the production web-host role, currently a Raspberry Pi 3 B+ (arm64,
1 GB RAM). Hardware is replaceable. [host.conf](../../hosts/viking/host.conf)
selects Mushr, Pawst, Snoot and Houstn metrics. Both public Pawst sites moved
to Viking on 2026-09-20 and passed external, LAN and reboot checks.

## Verified host preparation

On 2026-09-20 the operator completed Woodstock's Upstairs audio handoff, stopped
Viking's Snapclient with restart disabled, and verified key-only Tailscale SSH,
guest Wi-Fi attachment, persistent host/container firewall rules, security
updates and monitoring. See the [live hardening record](../operations/viking-hardening.md)
for exact addresses, permitted flows, tests and remaining limitations. The
[tracked baseline](../../hosts/viking/hardening/README.md) contains no secrets.

Use the [application platform runbook](../operations/application-platform.md)
for release deployment, rollback, public cutover and hardware replacement.
The patched configuration is running on Viking; commit and fleet-checkout
reconciliation remain pending. Public routing uses the separate `viking-prod`
tunnel. Do not reprovision from the old audio-role manifest.

## Monitoring and provisioning

Preserve Snoot's existing credentials. Viking's Houstn override runs Glances
only; the shared hub profile cannot start a hub here. Both agents are privileged
host-monitoring exceptions and must stay separate from public app containers.
Blanco initiates SSH through Tailscale; space-needle initiates monitoring through
Tailscale. Viking has no permission to initiate trusted-host connections.

For replacement hardware, use the [Pi guide](../operations/raspberry-pi.md) only
where applicable, and repeat the network/firewall tests with its actual interface
and addresses. Setup requires the production attestation and removes littledog's
Docker membership; it does not automatically install or overwrite firewall rules.

## Historical audio role

Viking previously used `192.168.86.26` on the trusted LAN and connected to
Snapserver `192.168.86.28:1704`; its MA player was `ma_viking`. These are historical
settings, not production dependencies. Woodstock now supplies Upstairs audio.

## Wi-Fi observations

Audio dropouts have been associated with Wi-Fi power saving. Test `sudo iw wlan0 set power_save off`; persist a proven fix through the host's actual network manager, not an assumed one.

The shared watchdog defaults to `wlan0`, `dhcpcd`, every five minutes; Viking now overrides the unit to `NetworkManager`. It acts only when the interface exists and has lost IPv4. **Confirm which network manager the installed OS uses**; if it is NetworkManager, set `WIFI_DHCP_UNIT=NetworkManager` in host.conf and rerun setup. Raspberry Pi installation choices can differ from the historical notes.

Inspect `/etc/default/loft-wifi-watchdog`, `/etc/cron.d/loft-wifi-watchdog` and `journalctl -t loft-wifi-watchdog`. A Git pull does not refresh the installed watchdog copy.
