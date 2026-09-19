# Reimage Calavera

Surface Pro 2, x86_64, powered dock and USB DAC. Reimaging interrupts Downstairs audio and erases the selected installation disk. Preserve needed credentials/configuration and confirm the target disk before starting.

1. Prepare a Debian 13 amd64 installer with firmware. Attach the Type Cover and powered dock; Volume-Down + Power boots removable media.
2. Set hostname `calavera`, initial user `adminhabl`, SSH server and standard utilities. Leave desktop/printing tasks unselected; the repo installs i3/lightdm itself.
3. Establish key-based SSH before running setup. Use the actual DHCP address; `192.168.86.35` is the configured fleet address, not proof of the installer's lease.
4. Install git, configure adminhabl's repository access, and clone the current main branch under `/srv/the-loft` as in [Pi checkout](raspberry-pi.md#checkout-and-credentials). Do not use the historical `calavera-fjord-swap` branch or a home-directory deployment.
5. Create all three environments from examples: Howlr (`client`, host ID calavera, server 192.168.86.28, `SOUND_DEVICE=plughw:Audio,0`), Houstn (`metrics`) and Snoot (new system credentials). Confirm the DAC card name with `aplay -l`.
6. Inspect [host.conf](../../hosts/calavera/host.conf) and [bootstrap](../../hosts/calavera/bootstrap), then run `sudo bash /srv/the-loft/setup.sh`. Bootstrap purges unused desktop/laptop packages, installs the dashboard, disables suspend and configures Wi-Fi recovery.
7. Reboot and verify key login, sudo, i3 autologin as rodnik, Firefox dashboard, Downstairs/All audio, fresh metrics and screen wake/blank behavior.

Current display scale is `I3_DPI=125` (about 130%), not the old 200% trial. Wi-Fi is `wlx501ac51167c0` with NetworkManager; inspect the interface on replacement hardware. Configure persistent MA login at the touchscreen if needed. Recheck group/stream IDs after MA migrations.

[Calavera's host page](../hosts/calavera.md) owns the retained DAC, Firefox, power-daemon and firmware-recovery observations. The old Ubuntu-to-Debian migration plan is historical only.
