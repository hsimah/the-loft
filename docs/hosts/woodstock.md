# woodstock

Original Surface Pro (not Surface Pro 2), intended to run Debian 13 amd64 with
the same Snapcast client, i3/Firefox touch dashboard and monitoring as
[Calavera](calavera.md).

**Status: Debian installed, rebooted, password SSH and sudo confirmed by the
operator.** Fleet provisioning is pending. Observed LAN address is
`192.168.86.37` (DHCP; reservation not confirmed). Woodstock will replace Viking
in **Upstairs and All**; keep Viking running until the new client is validated.

[host.conf](../../hosts/woodstock/host.conf) declares Howlr, Snoot and Houstn.
[bootstrap](../../hosts/woodstock/bootstrap) reuses Calavera's Surface dashboard
provisioning, with shared i3/kitty configuration and Woodstock's own settings.

## Observed hardware and networking

- Wi-Fi: `wlx28187844d6a5`, `mwifiex_usb`; `networking.service` active,
  NetworkManager and systemd-networkd inactive. The watchdog targets
  `networking`, every two minutes, with explicit `mwifiex_usb` recovery.
  Recovery is inherited from Calavera and still needs testing on this host.
- Ethernet: `enx281878b7cb4c`, disconnected during discovery.
- ALSA: card `PCH` (HDA Intel), card `Audio` (CONEXANT CNXT USB audio).
  The operator intends to use the Surface dock's 3.5 mm jack. Use
  `plughw:Audio,0` as the initial output and verify audible playback there;
  card enumeration alone does not establish the physical jack route.

## Establish key access first

From the admin laptop, install the normal fleet public key (select its `.pub`
file with `ssh-copy-id -i` if necessary):

```bash
ssh-copy-id adminhabl@192.168.86.37
ssh -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no adminhabl@192.168.86.37
```

Confirm the second connection succeeds and `sudo -v` works before setup disables
password SSH. Keep the original SSH session open during initial provisioning.

## Install Debian

1. Copy the official Debian 13 amd64 netinst ISO onto Ventoy's large data
   partition as a regular file. Do not flash the ISO over the Ventoy drive.
   Verify its SHA512 checksum against Debian's published `SHA512SUMS`.
2. Attach power, Type Cover and the USB. With the Surface off, hold Volume Down,
   press and release Power, then release Volume Down when the logo appears.
   Select the Debian ISO in Ventoy and use the normal boot mode.
3. Establish installer networking (Wi-Fi or USB Ethernet). Set hostname
   `woodstock` and initial user `adminhabl`. Leave the root password empty to
   give the initial user sudo access.
4. Back up any needed files before partitioning. Select the Surface's internal
   SSD by model and capacity, not a remembered `/dev/sdX` name. A guided
   whole-disk installation erases that SSD; never select the Ventoy USB.
5. Select SSH server and standard system utilities. Deselect desktop environments
   and printing tasks; repository provisioning installs i3 and lightdm.
6. Reboot into Debian and establish key-based SSH for `adminhabl` before running
   fleet setup, which disables SSH password authentication.

Installer sources: [Debian download](https://www.debian.org/download),
[Ventoy usage](https://www.ventoy.net/en/doc_start.html),
[Surface USB boot](https://support.microsoft.com/en-gb/surface/drivers-firmware/boot-surface-from-a-usb-device).

## Complete the fleet configuration after installation

Collect hardware details on Woodstock:

```bash
hostname
ip -br address
ls /sys/class/net
cat /proc/asound/cards
sudo apt-get update
sudo apt-get install -y git alsa-utils iw
iw dev
aplay -l
```

The prepared manifest retains Calavera's services, `rodnik` kiosk account and
`I3_DPI=125`, with dashboard `player=woodstock` and the observed Wi-Fi settings.
`I3_POWER_GROUPS` currently contains only the recorded **All** stream ID.
**Before cutover, obtain Upstairs' stream ID from Snapweb events, add it to the
manifest and rerun setup.** Until then, Upstairs-only playback will not wake or
keep the screen on. Recheck the recorded All ID too. This setting does not add
players to MA groups.

The listening test is deferred because speakers are not available. Provisioning
can proceed; audible output remains unverified. Once speakers are connected,
stop Howlr before testing the dock jack (start with the amplifier volume low):

```bash
loft-ctl stop howlr
sudo speaker-test -D plughw:Audio,0 -c 2 -t wav -l 2
loft-ctl start howlr
```

Follow the [Calavera reimage guide](../operations/calavera-reimage.md) for
checkout and provisioning, substituting Woodstock's identity and hardware:

- Howlr: `COMPOSE_PROFILES=client`, `HOST_ID=woodstock`,
  `SNAPSERVER_HOST=192.168.86.28`, and the verified ALSA output.
- Houstn: `COMPOSE_PROFILES=metrics`.
- Snoot: register a new Woodstock system in Beszel and use its credentials.

Use a fresh installation's machine identity and SSH host keys. Keep Calavera's
IP address, client identity and monitoring registration assigned to Calavera.
Use the latest `main` in Woodstock's checkout at `/srv/the-loft` before running
setup. After configuring repository access and creating or updating the checkout:

```bash
cd /srv/the-loft
cp hosts/woodstock/howlr.env.example services/howlr/.env
printf 'COMPOSE_PROFILES=metrics\n' > services/houstn/.env
cp services/snoot/.env.example services/snoot/.env
# Fill services/snoot/.env with the new Woodstock system credentials.
# Confirm key-only SSH login in a second session before this:
sudo bash setup.sh
```

Create these environments on the fresh host; preserve any existing credentials
if repeating the procedure. No credentials are stored in the host template.

After provisioning, verify SSH/sudo, kiosk autologin, touch input, audio,
monitoring, and screen wake/blank behavior before marking this host deployed.

## Upstairs cutover

1. Verify Woodstock's local dock audio, then Snapcast playback and dashboard.
2. Add the new Woodstock player to Upstairs and All in Music Assistant and
   remove Viking from those groups. Keep Woodstock's own host/client identity.
3. Confirm Upstairs and All playback, group volume and screen wake/idle behavior.
4. Stop Viking's Howlr client with `loft-ctl stop howlr` on Viking, then remove
   `howlr` from its manifest and update its documented role. Leave Snoot and
   Houstn monitoring enabled. This retirement has not yet been performed.
