#!/usr/bin/env bash
# loft-dashboard — Firefox kiosk on the Capcom dashboard, restarted on exit.
# niri starts it as rodnik; installed to /usr/local/bin by the bootstrap.
set -u
# shellcheck source=/dev/null
. /etc/default/loft-kiosk
profile="${HOME}/.local/share/loft-dashboard-firefox"

# A failed first load leaves Firefox on an error page with no retry, so wait
# for any HTTP answer (Home Assistant returns 400 until trusted_proxies is set;
# that still proves the network is up).
until curl -s -o /dev/null --max-time 5 "${KIOSK_DASHBOARD_URL%%#*}"; do
  sleep 2
done

while true; do
  firefox --kiosk --new-instance --profile "$profile" "$KIOSK_DASHBOARD_URL"
  sleep 2
done
