# calavera

Surface Pro 2, x86_64, Debian 13, 4 GB RAM, touchscreen and powered dock. LAN `192.168.86.35`. It is the always-on Downstairs Snapcast client, replacing Fjord, and a Music Assistant touch dashboard. The former vinyl/Spinnik role is retired.

[host.conf](../../hosts/calavera/host.conf) declares Howlr client, Snoot and Houstn metrics. [bootstrap](../../hosts/calavera/bootstrap) owns desktop provisioning; [the reimage guide](../operations/calavera-reimage.md) covers installation.

## Audio

The dock's USB DAC reports as `CONEXANT CNXT Audio`, ALSA card `Audio`. Use:

```bash
COMPOSE_PROFILES=client
SNAPSERVER_HOST=192.168.86.28
SOUND_DEVICE=plughw:Audio,0
HOST_ID=calavera
```

The recorded MA player `ma_calavera` belongs to Downstairs and All. Confirm group membership in MA after upgrades. The dock's 3.5mm output produced no working codec/jack path in the original Linux investigation; the tablet jack worked, but the dock USB DAC was chosen. These are hardware observations, not a reason to change an already working audio path.

```bash
cat /proc/asound/cards
sudo aplay -l
sudo amixer -c Audio
sudo docker logs howlr-snapclient --tail 50
```

If the DAC is absent, check **dock power** first: the tablet battery can keep the computer alive while dock USB devices are off. Verify card identity and effective container device permissions before changing UIDs. Test audio locally with `sudo speaker-test -D plughw:Audio,0 -c 2 -t wav -l 2` when the device is not in use.

## Desktop and display power

lightdm autologs `rodnik` into i3. This display account has video/input/audio groups, no sudo and no Docker access. Super+Return opens kitty; it does not grant an admin shell. i3 config lives under [hosts/calavera/i3](../../hosts/calavera/i3).

The generated `loft-dashboard` launcher waits for the dashboard URL and runs Firefox kiosk in a restart loop. `I3_DASHBOARD_URL` selects MA's now-playing view. `I3_DPI=125` gives approximately 130% scale through Xresources and the Firefox profile. `MOZ_USE_XINPUT2=1` and touch/kinetic-scroll preferences enable swipe scrolling. A recorded Chromium 150.x crashpad/SIGTRAP failure led to Firefox ESR; treat that as a version-specific incident.

The bootstrap masks sleep targets, ignores lid switches, removes auto-rotation and purges unused desktop/laptop services. It also installs [loft-dashboard-power](../../control-plane/loft-dashboard-power.py) and its systemd unit. Automatic DPMS timeouts are disabled; the daemon wakes on watched Snapcast streams and blanks when no watched stream is playing and input idle reaches 600 seconds. Local input can wake the display.

`I3_POWER_GROUPS` contains observed stream IDs for Downstairs/All, matched against `Music Assistant - <id>`. They were obtained from Snapweb events, not assumed from a documented MA contract. MA's own WebSocket did not yield events to the tested plain client, so the daemon uses Snapcast's `ws://192.168.86.28:1780/jsonrpc`. Recheck stream IDs after changing groups.

```bash
systemctl status loft-dashboard-power
journalctl -u loft-dashboard-power --since '10 min ago'
systemctl status lightdm
```

For a screen that never wakes, compare actual stream IDs/events with `/etc/default/loft-dashboard-power`. For one that never blanks, check playing states and whether input keeps **resetting** the idle timer. For a blank dashboard, test the configured URL from this host; rerun setup after changing URL/DPI or installed scripts. The dedicated Firefox profile preserves login state, but migrations may require touchscreen login again.

## Wi-Fi recovery record

The Marvell USB adapter uses `wlx501ac51167c0` under NetworkManager. Host config chooses a two-minute watchdog and explicit `WIFI_FW_MODULE=mwifiex_usb`. The udev rule disables USB autosuspend for vendor 1286.

**Recorded 2026-07-30:** firmware crashes left the interface unusable; restarting NetworkManager alone did not recover it. Module reload did. Dynamic sysfs discovery incorrectly identified usbcore, so the module is now explicit. Cron also needed `/sbin` and `/usr/sbin` on PATH. Preserve both constraints.

The current watchdog does not grep dmesg: when the interface exists but lacks IPv4 and firmware recovery is enabled, it reloads the configured module and restarts NetworkManager. It does not detect every network failure (for example a dead link retaining IPv4).

```bash
journalctl -t loft-wifi-watchdog --since '1 day ago'
# Same invocation as cron; use a console if loss of this SSH connection matters:
sudo sh -c '. /etc/default/loft-wifi-watchdog && /usr/local/bin/loft-wifi-watchdog'
```

Earlier fixes were present in Git but not copied into `/usr/local/bin`; rerun setup after watchdog changes and compare the installed script. Manual module reload is a last-resort host operation; expect it to interrupt networking.
