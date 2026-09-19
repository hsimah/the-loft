# viking

Raspberry Pi 3 B+, arm64, 1 GB RAM, Upstairs Snapcast client. LAN address `192.168.86.26`; hostname taken from a Vikingfjord bottle. [host.conf](../../hosts/viking/host.conf) declares Howlr, Snoot and Houstn. There is no media volume or `/opt` service data directory.

## Provisioning

Use the [current Pi guide](../operations/raspberry-pi.md). Select `COMPOSE_PROFILES=client` for Howlr and `metrics` for Houstn. Configure the [Beszel agent](../services/snoot.md) with the new system's credentials.

Howlr needs `SNAPSERVER_HOST=192.168.86.28`, `HOST_ID=viking` and the actual ALSA `SOUND_DEVICE`. Inspect cards with `aplay -l`; use a stable card name when needed. The recorded Music Assistant player is `ma_viking`, in Upstairs and All groups. Confirm current UI state after re-provisioning.

```bash
loft-ctl health
sudo docker logs howlr-snapclient --tail 50
nc -zv 192.168.86.28 1704
```

Keep inference and Music Assistant server workloads off this low-memory client. A wrong profile is one possible source of memory pressure; confirm OOMKilled before diagnosing exit 137.

## Wi-Fi observations

Audio dropouts have been associated with Wi-Fi power saving. Test `sudo iw wlan0 set power_save off`; persist a proven fix through the host's actual network manager, not an assumed one.

The watchdog installed by setup defaults to `wlan0`, `dhcpcd`, every five minutes. It acts only when the interface exists and has lost IPv4. **Confirm which network manager the installed OS uses**; if it is NetworkManager, set `WIFI_DHCP_UNIT=NetworkManager` in host.conf and rerun setup. Raspberry Pi installation choices can differ from the historical notes.

Inspect `/etc/default/loft-wifi-watchdog`, `/etc/cron.d/loft-wifi-watchdog` and `journalctl -t loft-wifi-watchdog`. A Git pull does not refresh the installed watchdog copy.
