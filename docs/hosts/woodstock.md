# woodstock

Surface Pro (1st gen), x86_64, Debian 13, touchscreen and powered dock. LAN `192.168.86.37`. Upstairs Snapcast client and Music Assistant touch dashboard. [host.conf](../../hosts/woodstock/host.conf) runs Howlr client, Snoot and Houstn metrics; [bootstrap](../../hosts/woodstock/bootstrap) reuses Calavera's desktop provisioning.

## Audio

Output is the dock's USB DAC (`CONEXANT CNXT Audio`, ALSA card `Audio`).

```bash
COMPOSE_PROFILES=client
SNAPSERVER_HOST=192.168.86.28
SOUND_DEVICE=plughw:Audio,0
HOST_ID=woodstock
```

Its MA player is in Upstairs and All. If the DAC is missing, check **dock power** first — the tablet battery keeps the computer up while dock USB is off.

`loft-dac` (from `AUDIO_*` in host.conf) runs whenever udev sees the card: it disables USB runtime suspend on the DAC (suspend between streams causes a pop or clipped start) and sets the hardware volume to `AUDIO_VOLUME`, since the card otherwise powers up at ~50%. Change the level in host.conf and rerun setup.

```bash
cat /proc/asound/cards
sudo docker logs howlr-snapclient --tail 50
journalctl -u loft-dac
sudo speaker-test -D plughw:Audio,0 -c 2 -t wav -l 2   # with howlr stopped
```

## Desktop and display power

lightdm autologs `rodnik` (video/input/audio only; no sudo/Docker) into i3, which runs `loft-dashboard`: Firefox ESR kiosk on `I3_DASHBOARD_URL` in a restart loop. `I3_DPI=125` ≈ 130% scale. Config: [hosts/woodstock/i3](../../hosts/woodstock/i3).

Bootstrap masks sleep, ignores the lid, removes auto-rotation and installs [loft-dashboard-power](../../control-plane/loft-dashboard-power.py). It watches Snapcast's `ws://192.168.86.28:1780/jsonrpc` and wakes the screen when a stream in `I3_POWER_GROUPS` (Upstairs and All) plays, blanking after 600 s idle with nothing playing. Stream IDs come from Snapserver's `Server.GetStatus`; recheck them after changing MA groups.

```bash
systemctl status loft-dashboard-power lightdm
journalctl -u loft-dashboard-power --since '10 min ago'
```

Screen never wakes: compare live stream IDs with `/etc/default/loft-dashboard-power`. Never blanks: check playing state and whether input keeps resetting idle. Rerun setup after changing URL/DPI or scripts.

## Wi-Fi

Marvell USB adapter `wlx28187844d6a5` under `networking.service` (not NetworkManager); udev disables USB autosuspend for vendor 1286. The watchdog runs every 2 minutes and reloads `mwifiex_usb` when the interface has no IPv4, as on Calavera; recovery is untested here.

```bash
journalctl -t loft-wifi-watchdog --since '1 day ago'
sudo sh -c '. /etc/default/loft-wifi-watchdog && /usr/local/bin/loft-wifi-watchdog'
```

Setup copies the watchdog to `/usr/local/bin`; rerun setup after changing it.

## Reimage

Reimaging erases the disk and interrupts Upstairs audio.

1. Debian 13 amd64 installer with firmware. Attach Type Cover and dock; hold Volume Down + Power to boot USB.
2. Hostname `woodstock`, user `adminhabl`, empty root password, SSH server + standard utilities only (setup installs i3/lightdm).
3. Set up key SSH, install git, clone to `/srv/the-loft` per [fresh host](../scripts/setup.md#fresh-host).
4. Create Howlr (as above), Houstn (`COMPOSE_PROFILES=metrics`) and Snoot (new Beszel system) `.env` files.
5. `sudo bash setup.sh`, reboot, and verify SSH/sudo, kiosk, audio, metrics and screen wake/blank.
