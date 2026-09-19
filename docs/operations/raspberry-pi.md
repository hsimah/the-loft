# Provision a fleet Pi

Applies to Viking and Fjord (Pi 3 B+, 64-bit OS). Use a supported Debian-based Raspberry Pi OS Lite image with the fleet's Docker prerequisites. Set hostname and network settings in the imager, create `adminhabl`, and enable SSH with your public key. Confirm the target SD card before writing it.

| Host | Services | Environments |
|---|---|---|
| Viking | Howlr client, Snoot, Houstn metrics | howlr, snoot, houstn |
| Fjord | Snoot, Houstn metrics | snoot, houstn |

After boot, find the address through DHCP or `<hostname>.local`. Verify `hostname` matches an existing manifest and `uname -m` is `aarch64`. Confirm key login before setup disables password SSH.

## Checkout and credentials

Run as adminhabl. Give this account a read-only GitHub deploy key if needed, registered on `hsimah-services/the-loft`; test Git access before cloning.

```bash
sudo apt-get update
sudo apt-get install -y git
sudo install -d -o adminhabl -g adminhabl /srv/the-loft
git clone git@github.com:hsimah-services/the-loft.git /srv/the-loft
cd /srv/the-loft
cp services/snoot/.env.example services/snoot/.env
cp services/houstn/.env.example services/houstn/.env
```

Set Houstn's profile to `metrics`. Obtain the new system's Beszel credentials through [Snoot onboarding](../services/snoot.md).

On **Viking only**, create Howlr's environment from its example and set `COMPOSE_PROFILES=client`, `SNAPSERVER_HOST=192.168.86.28`, `HOST_ID=viking` and the correct ALSA device. Do not create Howlr's environment on Fjord. MA already exists on space-needle; there is no future server rollout to wait for.

## Provision and verify

```bash
sudo bash setup.sh
sudo passwd adminhabl
sudo sshd -T | grep -E 'allowusers|passwordauthentication'
id littledog
loft-ctl health
```

Setup manages adminhabl's bash/input configuration. Keep the current SSH session open while checking a second key login and sudo. Review OS-installed sudoers drop-ins if passwordless sudo remains; validate changes with `visudo` rather than removing unfamiliar files blindly.

Confirm the actual network manager. The watchdog defaults to dhcpcd; if the OS uses NetworkManager, set the correct WIFI_DHCP_UNIT in host.conf and rerun setup. See [Viking's Wi-Fi checks](../hosts/viking.md#wi-fi-observations).

Check fresh Beszel/Glances metrics from the hub. On Viking, confirm Upstairs playback. The live network manager, audio device and credentials are installation-specific and cannot be inferred from a successful Compose syntax check.
