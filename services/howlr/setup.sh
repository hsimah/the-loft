#!/usr/bin/env bash
# Howlr service setup — sourced by setup.sh
# Expects: REPO_DIR, info function available in caller

# Clients get loft-snapclient-volume, which sets this room's Snapcast volume
# once per boot. Removed first so a host that stops being a client loses it.
HOWLR_ENV="${REPO_DIR}/services/howlr/.env"
if [[ -f /etc/systemd/system/loft-snapclient-volume.service ]]; then
  systemctl disable loft-snapclient-volume.service 2>/dev/null || true
fi
rm -f /etc/systemd/system/loft-snapclient-volume.service \
  /etc/default/loft-snapclient-volume /usr/local/bin/loft-snapclient-volume
if [[ -f "$HOWLR_ENV" ]] \
  && grep -qE '^[[:space:]]*COMPOSE_PROFILES=([^#[:space:]]*,)?client([,[:space:]]|$)' "$HOWLR_ENV"; then
  install -o root -g root -m 755 "${REPO_DIR}/services/howlr/snapclient-volume.sh" \
    /usr/local/bin/loft-snapclient-volume
  install -o root -g root -m 644 "${REPO_DIR}/services/howlr/loft-snapclient-volume.service" \
    /etc/systemd/system/loft-snapclient-volume.service
  echo "HOWLR_ENV=\"${HOWLR_ENV}\"" > /etc/default/loft-snapclient-volume
  systemctl daemon-reload
  # Enabled for the next boot only: starting it now would override MA's volume.
  systemctl enable loft-snapclient-volume.service
  info "Installed loft-snapclient-volume (applies on next boot)"
else
  systemctl daemon-reload
  info "Howlr is not a client here; loft-snapclient-volume not installed"
fi
