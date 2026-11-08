#!/usr/bin/env bash
# kiosk-debloat.sh — remove the desktop and laptop tasks the Debian installer
# adds to Surface kiosks. Sourced as root by the Calavera/Woodstock and Lady
# Grey bootstraps; expects info/warn from setup.sh. Safe to re-run.
# Install every package the kiosk needs BEFORE sourcing this: anything left as
# a dependency of the purged tasks is taken by autoremove.

# `apt-get purge` aborts the whole transaction on one unknown package name, so
# a single rename in a later release would silently skip an entire list.
# Purge only what is actually installed.
purge_pkgs() {
  local pkgs=() p
  for p in "$@"; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'ok installed' && pkgs+=("$p")
  done
  (( ${#pkgs[@]} )) || return 0
  apt-get purge -y -qq "${pkgs[@]}" > /dev/null 2>&1 || true
}

# ── Remove desktop/laptop-task cruft ───────────────────────────────────────
# The Debian installer ticks "print server" by default and auto-selects the
# "laptop" task on hardware that reads as a laptop (the Surface Pro 2 does),
# even when "Debian desktop environment" is unticked. That drags in a full
# peripheral stack an unattended kiosk never touches: printing (cups),
# Bluetooth, mDNS/service discovery (avahi), cellular modem support,
# PackageKit, and speech synthesis. Purge it so it can't come back on a
# later `apt upgrade` either. Safe to re-run; no-ops once already removed.
info "Removing desktop/laptop-task cruft (printing, Bluetooth, mDNS, modem, PackageKit, speech)..."
systemctl disable --now \
  cups.service cups.socket cups.path cups-browsed.service \
  bluetooth.service avahi-daemon.service avahi-daemon.socket \
  ModemManager.service upower.service power-profiles-daemon.service \
  switcheroo-control.service fwupd.service fwupd-refresh.timer \
  colord.service accounts-daemon.service 2>/dev/null || true
purge_pkgs \
  cups cups-browsed cups-daemon cups-client cups-common cups-core-drivers \
  cups-filters cups-filters-core-drivers cups-ipp-utils cups-pk-helper \
  cups-ppdc cups-server-common python3-cups python3-cupshelpers \
  bluetooth bluez bluez-obexd gnome-bluetooth-sendto \
  avahi-daemon avahi-utils \
  modemmanager \
  packagekit packagekit-tools gstreamer1.0-packagekit \
  speech-dispatcher speech-dispatcher-audio-plugins speech-dispatcher-espeak-ng \
  upower power-profiles-daemon switcheroo-control fwupd colord \
  accountsservice
apt-get autoremove -y -qq > /dev/null

# ── Remove full desktop-environment task cruft ─────────────────────────────
# Separate from the laptop-task cleanup above: the Debian installer can also
# tick task-desktop (the "Debian desktop environment" meta-task), which drags
# in a full GNOME desktop (calculator, calendar, contacts, maps, music,
# weather, terminal, tweaks, remote-desktop...), the Evolution
# mail/groupware suite, Chromium, and the entire LibreOffice suite. None of it
# is used — a kiosk runs only its compositor and firefox-esr (Chromium crashed
# on trixie; see the Calavera bootstrap). Purge the task metapackages plus each
# unused suite explicitly, so it can't come back on a later `apt upgrade`. Safe to re-run; no-ops once
# already removed. NetworkManager/wpasupplicant/wireless tooling and
# pipewire/gstreamer are deliberately left alone — WiFi and audio playback
# are load-bearing on the kiosks.
info "Removing desktop-task cruft (GNOME apps, Evolution, Chromium, LibreOffice)..."
purge_pkgs \
  chromium \
  libreoffice-base-core libreoffice-calc libreoffice-common libreoffice-core \
  libreoffice-draw libreoffice-gnome libreoffice-gtk3 libreoffice-help-common \
  libreoffice-help-en-us libreoffice-impress libreoffice-math \
  libreoffice-style-colibre libreoffice-style-elementary \
  libreoffice-uiconfig-calc libreoffice-uiconfig-common \
  libreoffice-uiconfig-draw libreoffice-uiconfig-impress \
  libreoffice-uiconfig-math libreoffice-uiconfig-writer libreoffice-writer \
  libstaroffice-0.0-0 \
  evolution evolution-common evolution-data-server evolution-data-server-common \
  evolution-ews evolution-plugin-bogofilter evolution-plugin-pstimport \
  evolution-plugins \
  gnome-calculator gnome-calendar gnome-characters gnome-clocks \
  gnome-connections gnome-contacts gnome-disk-utility gnome-font-viewer \
  gnome-logs gnome-maps gnome-music gnome-remote-desktop gnome-snapshot \
  gnome-sound-recorder gnome-sushi gnome-system-monitor gnome-terminal \
  gnome-text-editor gnome-tour gnome-tweaks gnome-user-docs gnome-weather \
  nautilus file-roller baobab evince totem totem-plugins shotwell \
  simple-scan rygel-playbin rygel-tracker loupe yelp zenity tecla seahorse \
  task-desktop task-laptop laptop-detect dmidecode

# locales-all alone is ~236 MB; the configured locale comes from `locales`.
info "Removing surplus locales and installer docs..."
purge_pkgs \
  locales-all util-linux-locales krb5-locales \
  debian-faq doc-debian installation-report reportbug apt-listchanges \
  kitty-doc xterm inetutils-telnet
apt-get autoremove -y -qq > /dev/null
apt-get clean
