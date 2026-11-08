#!/usr/bin/env bash
# loft-idle — swayidle timeouts for the kiosk: photo frame after
# KIOSK_PHOTO_IDLE seconds, panel off after KIOSK_SCREEN_OFF_IDLE (0 disables
# either). Any input undoes both. niri starts it as rodnik.
set -u
# shellcheck source=/dev/null
. /etc/default/loft-kiosk

args=(-w)
if (( ${KIOSK_PHOTO_IDLE:-0} > 0 )); then
  args+=(timeout "$KIOSK_PHOTO_IDLE" '/usr/local/bin/loft-photo-frame start'
         resume '/usr/local/bin/loft-photo-frame stop')
fi
if (( ${KIOSK_SCREEN_OFF_IDLE:-0} > 0 )); then
  args+=(timeout "$KIOSK_SCREEN_OFF_IDLE" 'niri msg action power-off-monitors'
         resume 'niri msg action power-on-monitors')
fi
exec swayidle "${args[@]}"
