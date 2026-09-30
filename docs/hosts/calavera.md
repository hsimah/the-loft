# calavera

Surface Pro 2, x86_64, Debian 13, 4 GB RAM, touchscreen and powered dock. LAN `192.168.86.35`. Downstairs Snapcast client and Music Assistant touch dashboard. [host.conf](../../hosts/calavera/host.conf) runs Howlr client, Snoot and Houstn metrics; [bootstrap](../../hosts/calavera/bootstrap) owns the desktop.

## Audio

Output is the dock's USB DAC (`CONEXANT CNXT Audio`, ALSA card `Audio`). The dock's 3.5 mm jack does not work under Linux.

```bash
COMPOSE_PROFILES=client
SNAPSERVER_HOST=192.168.86.28
SOUND_DEVICE=plughw:Audio,0
HOST_ID=calavera
```

MA player `ma_calavera` is in Downstairs and All. If the DAC is missing, check **dock power** first — the tablet battery keeps the computer up while dock USB is off.

```bash
cat /proc/asound/cards
sudo docker logs howlr-snapclient --tail 50
sudo speaker-test -D plughw:Audio,0 -c 2 -t wav -l 2   # with howlr stopped
```

## Desktop and display power

lightdm autologs `rodnik` (video/input/audio only; no sudo/Docker) into i3, which runs `loft-dashboard`: Firefox ESR kiosk on `I3_DASHBOARD_URL` in a restart loop. `I3_DPI=125` ≈ 130% scale. Chromium 150.x crashed here, hence Firefox. Config: [hosts/calavera/i3](../../hosts/calavera/i3).

Bootstrap masks sleep, ignores the lid, removes auto-rotation and installs [loft-dashboard-power](../../control-plane/loft-dashboard-power.py). It watches Snapcast's `ws://192.168.86.28:1780/jsonrpc` (MA's own WebSocket gave no events) and wakes the screen when a stream in `I3_POWER_GROUPS` plays, blanking after 600 s idle with nothing playing. Stream IDs were read from Snapweb events; recheck them after changing MA groups.

```bash
systemctl status loft-dashboard-power lightdm
journalctl -u loft-dashboard-power --since '10 min ago'
```

Screen never wakes: compare live stream IDs with `/etc/default/loft-dashboard-power`. Never blanks: check playing state and whether input keeps resetting idle. Rerun setup after changing URL/DPI or scripts.

## Wi-Fi

Marvell USB adapter `wlx501ac51167c0` under NetworkManager; udev disables USB autosuspend for vendor 1286. Firmware crashes need a **module reload** (`mwifiex_usb`), not just a NetworkManager restart, so the watchdog runs every 2 minutes with `WIFI_FW_MODULE` set explicitly (sysfs discovery returns `usbcore`). Cron needs `/sbin` and `/usr/sbin` on PATH. The watchdog only acts when the interface has no IPv4.

```bash
journalctl -t loft-wifi-watchdog --since '1 day ago'
sudo sh -c '. /etc/default/loft-wifi-watchdog && /usr/local/bin/loft-wifi-watchdog'
```

Setup copies the watchdog to `/usr/local/bin`; rerun setup after changing it.

## Reimage

Reimaging erases the disk and interrupts Downstairs audio.

1. Debian 13 amd64 installer with firmware. Attach Type Cover and dock; hold Volume Down + Power to boot USB.
2. Hostname `calavera`, user `adminhabl`, empty root password, SSH server + standard utilities only (setup installs i3/lightdm).
3. Set up key SSH, install git, clone to `/srv/the-loft` per [fresh host](../scripts/setup.md#fresh-host).
4. Create Howlr (as above), Houstn (`COMPOSE_PROFILES=metrics`) and Snoot (new Beszel system) `.env` files.
5. `sudo bash setup.sh`, reboot, and verify SSH/sudo, kiosk, audio, metrics and screen wake/blank.
