# lady-grey

Surface Pro 3, x86_64, **Fedora 45** (the only non-Debian host), touchscreen. LAN `192.168.86.25`. Home Assistant wall tablet: a [Capcom](../services/capcom.md) dashboard, with the Hubbl photo frame when idle. No audio. [host.conf](../../hosts/lady-grey/host.conf) runs Snoot, Houstn metrics and Pupshow; [bootstrap](../../hosts/lady-grey/bootstrap) owns the desktop.

**Provisioned from the unmerged `feat/lady-grey` branch.** Output name, scale, the dashboard and the photo frame are not verified yet.

## Desktop

Unlike Calavera and Woodstock (i3/Xorg), Lady Grey runs **niri** with the **Noctalia** shell on Wayland. Both configs come from blanco (`hsimah/blanco` on kennl). greetd autologs `rodnik` into `loft-kiosk-session`, which restarts `niri-session` whenever it exits. niri ([config.kdl](../../hosts/lady-grey/niri/config.kdl)) has blanco's layout and binds, and starts:

- `loft-dashboard`: Firefox kiosk on `KIOSK_DASHBOARD_URL` in a restart loop, once the URL answers. A window rule opens Firefox maximized under Noctalia's bar and refuses its kiosk fullscreen request.
- `loft-idle`: swayidle. After `KIOSK_PHOTO_IDLE` s without input, `loft-photo-frame start` opens a second Firefox on Pupshow and fullscreens it by PID over the dashboard and bar; the next touch closes it. It does nothing while Pupshow's `/health` fails. `KIOSK_SCREEN_OFF_IDLE` > 0 also powers the panel off.

Settings come from host.conf via `/etc/default/loft-kiosk`; rerun setup after changing them. Sleep targets are masked and the lid is ignored. Mod+T opens kitty, Mod+Space fuzzel; Mod+Shift+E restarts niri. Output scale is `NIRI_SCALE` on `NIRI_OUTPUT`; check the name with `niri msg outputs`.

Noctalia ([config.toml](../../hosts/lady-grey/noctalia/config.toml)) is blanco's with its idle lock, suspend and screen-off disabled, and without audio, Bluetooth or power-profile widgets. It runs as a user service with the niri session. Setup rewrites `~rodnik/.config/noctalia/config.toml`, so make lasting changes in the repo, not the settings UI. Wallpapers go in `/home/rodnik/Pictures/Wallpapers`; Noctalia themes niri from them through `noctalia.kdl`, which setup seeds empty because niri refuses a missing include.

```bash
systemctl status greetd
sudo journalctl -b _UID=$(id -u rodnik) --since '10 min ago'   # niri, Firefox, swayidle
sudo -u rodnik XDG_RUNTIME_DIR=/run/user/$(id -u rodnik) systemctl --user status noctalia
```

## Fedora

niri, Noctalia, greetd, swayidle, kitty and Firefox come from Fedora's repos, installed without weak dependencies, and update with `sudo dnf upgrade`; reboot after a niri update. Fedora is supported for about 13 months, so move to the next release once a year with `dnf system-upgrade`, then rerun setup.

Differences from the Debian hosts, all handled by setup and the bootstrap:

- The admin group is `wheel`; cron is `cronie`; Docker CE comes from Docker's Fedora repo.
- greetd runs on VT1 in place of `getty@tty1`; Ctrl+Alt+F2 gives a text console.
- firewalld is on. The bootstrap opens 61208 (Glances) and 45876 (Beszel agent); SSH is open by default. Pupshow listens on loopback only.
- SELinux is enforcing. Docker CE does not label containers (`selinux-enabled` is off), so bind mounts need no `:z`. If the kiosk does not start, check `sudo ausearch -m avc -ts boot`.

## Dashboard login

Log in once on the tablet as a dedicated non-admin Capcom user with **Keep me logged in**; the token persists in the kiosk profile `/home/rodnik/.local/share/loft-dashboard-firefox`. Set that user's default dashboard in its profile, or put the dashboard path in `KIOSK_DASHBOARD_URL`.

## Photo frame

[Pupshow](../../services/pupshow/docker-compose.yml) is Immich Kiosk on `127.0.0.1:3000`, never on the LAN. In Hubbl, create a non-admin user, share the frame album with it, and create its API key. Copy [.env.example](../../services/pupshow/.env.example) to `.env` with that key and the album ID, then `loft-ctl start pupshow`. Setup skips Pupshow until `.env` exists. Anyone with the key sees what that user sees; never use an admin key.

## Wi-Fi

The Surface Pro 3 uses a Marvell 88W8797 on PCIe (`mwifiex_pcie`), the same firmware family that crashes on Calavera. The watchdog runs every 2 minutes and reloads `mwifiex_pcie` when the interface loses IPv4. The interface is `wlp2s0`, under NetworkManager (`nmcli device`).

## Install

1. Fedora 45 Everything netinstall, x86_64 ([releases](https://fedoraproject.org/misc#everything)). Hold Volume Down + Power to boot USB with the Type Cover attached; Secure Boot can stay on.
2. Software Selection: Minimal Install with the **Common NetworkManager Submodules** add-on (without it the installed system has no Wi-Fi support). Host name `lady-grey`. User `adminhabl`, made administrator; root account disabled. Join Wi-Fi in Network & Host Name: the install downloads packages.
3. `sudo dnf install git`, key SSH, clone to `/srv/the-loft` per [fresh host](../scripts/setup.md#fresh-host).
4. Record the address and Wi-Fi interface in host.conf. Create Houstn (`COMPOSE_PROFILES=metrics`), Snoot (new Beszel system) and, when ready, Pupshow `.env` files.
5. `/srv/the-loft/loft-ctl setup`, reboot, and check: kiosk on the dashboard, touch scrolling, photo frame after idle and dismissed by touch, metrics, and recovery after rebooting with Capcom down.
