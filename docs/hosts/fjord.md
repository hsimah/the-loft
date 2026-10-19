# fjord

Raspberry Pi 3 B+, arm64, `192.168.86.30`, no media volume. LAN-only dev/test, plus a Howlr client playing to a Bluetooth speaker. [host.conf](../../hosts/fjord/host.conf) runs Mushr (LAN proxy, no tunnel or DNS), Pawst dev/test, Howlr client, Snoot and Houstn metrics. **Not yet validated live.**

Conventions for environments, hostnames (`<app>.<dev|test>.fjord`) and promotion to Viking are in the [application platform](../operations/application-platform.md). Space-needle's DNS already resolves `*.fjord`; each name still needs a Caddy route. Never put Fjord behind a tunnel or port forward.

```bash
loft-ctl start mushr pawst
loft-ctl health
```

Pawst healthchecks fail until the blog is deployed to each environment; setup only creates empty roots. The hbla.ke holding page ships in the repo.

Confirm which network manager the OS uses. The Wi-Fi watchdog defaults to `dhcpcd`; set `WIFI_DHCP_UNIT` in host.conf if it differs, then rerun setup.

## Audio

Snapclient plays through the host's bluealsa daemon to the speaker. The [override](../../hosts/fjord/overrides/howlr/docker-compose.override.yml) builds [Dockerfile.snapclient](../../services/howlr/Dockerfile.snapclient) (Debian snapclient plus the bluealsa ALSA plugin) and mounts the system D-Bus socket. The image's Debian release must match the host's (`/etc/os-release`), because the plugin and the daemon communicate over D-Bus. The [bootstrap](../../hosts/fjord/bootstrap) installs BlueZ and bluealsa (A2DP source only) and, once `BT_SPEAKER_MAC` is set, adds [loft-bt-speaker](../../control-plane/loft-bt-speaker.sh). That cron job reconnects the speaker every minute while it is disconnected, which covers the speaker being switched off and on again.

```bash
COMPOSE_PROFILES=client
SNAPSERVER_HOST=192.168.86.28
SOUND_DEVICE=bluealsa:DEV=<speaker MAC>,PROFILE=a2dp
HOST_ID=fjord
SNAPCLIENT_LATENCY=220
```

Pair once after the first setup run, with the speaker in pairing mode:

```bash
sudo bluetoothctl
#   power on / scan on / pair <MAC> / trust <MAC> / connect <MAC> / scan off
```

Then set `BT_SPEAKER_MAC` in host.conf (the speaker is an NH-69), rerun setup and rebuild Howlr. Fjord owns the speaker: it stays connected and reconnects within a minute, so phones cannot pair with it directly. Play to it through MA. Volume is controlled by MA through Snapcast's software mixer, so set the speaker's own volume high.

**Wi-Fi and Bluetooth share one radio and antenna on the Pi 3 B+.** On 2.4 GHz, A2DP stutters under network load. Keep Fjord on 5 GHz (`iw dev wlan0 link` should show a frequency of 5xxx). If it shows 2.4 GHz, lock the band in the network manager's profile.

```bash
bluetoothctl info <MAC> | grep -E 'Connected|Trusted'
journalctl -u bluealsa --since "1 hour ago"
journalctl -t loft-bt-speaker --since "1 day ago"
sudo docker logs howlr-snapclient --tail 50
```

### Sync with Woodstock

The speaker is within earshot of Woodstock, so Fjord's output has to line up with it. Snapcast compensates for the delay that bluealsa reports. That includes the speaker's own delay only if it supports A2DP 1.3 delay reporting. Whatever remains is buffering inside the speaker, so set it with `SNAPCLIENT_LATENCY`, which makes Fjord play that many milliseconds early. Snapweb's per-client latency setting adds to this value, so keep only one of them non-zero.

1. Play a track with sharp transients (a click or metronome track) to a group containing Woodstock and Fjord.
2. Stand about the same distance from both speakers. Sound travels about 3 ms per metre, so alignment is exact only where the two distances are equal.
3. In Snapweb, adjust Fjord's latency slider live until the doubled attack disappears. If Fjord sounds late, increase the value. For a precise number, record both speakers on a phone and measure the offset in an audio editor.
4. Copy the value into `SNAPCLIENT_LATENCY`, set Snapweb back to 0, and run `loft-ctl rebuild howlr`. The NH-69 lines up with Woodstock at 220 ms.

Check the value again after the speaker reconnects and after an hour of playback. A codec change or speaker-side clock drift shows up as a new offset. bluealsa on Debian negotiates SBC with most speakers; AAC is not built.
