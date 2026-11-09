#!/usr/bin/env bash
# loft-photo-frame start|stop — show or close the Pupshow photo frame over the
# dashboard. loft-idle calls start after KIOSK_PHOTO_IDLE seconds without input
# and stop on the next input. Installed to /usr/local/bin by the bootstrap.
set -u
# shellcheck source=/dev/null
. /etc/default/loft-kiosk
profile="${HOME}/.local/share/loft-photos-firefox"
pidfile="${XDG_RUNTIME_DIR:-/tmp}/loft-photo-frame.pid"

running() { [[ -f "$pidfile" ]] && kill -0 "$(< "$pidfile")" 2>/dev/null; }

case "${1:-}" in
  start)
    running && exit 0
    # Pupshow down or not configured: leave the dashboard showing.
    curl -fs -o /dev/null --max-time 3 "${KIOSK_PHOTO_URL}/health" || exit 0
    firefox --kiosk --new-instance --profile "$profile" "$KIOSK_PHOTO_URL" \
      > /dev/null 2>&1 &
    echo $! > "$pidfile"
    ;;
  stop)
    running && kill "$(< "$pidfile")"
    rm -f "$pidfile"
    ;;
  *)
    echo "usage: loft-photo-frame start|stop" >&2
    exit 2
    ;;
esac
