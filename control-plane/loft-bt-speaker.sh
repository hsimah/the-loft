#!/usr/bin/env bash
# loft-bt-speaker.sh — reconnect a paired Bluetooth speaker.
#
# Installed by Fjord's bootstrap to /usr/local/bin/loft-bt-speaker, invoked by
# /etc/cron.d/loft-bt-speaker, config sourced from /etc/default/loft-bt-speaker
# (BT_SPEAKER_MAC from host.conf).
#
# BlueZ retries a dropped link only briefly. A speaker that was switched off
# waits for the source to connect when it comes back, so poll. A speaker that
# is off or out of range fails quietly; only a new connection is logged.
set -u

: "${BT_SPEAKER_MAC:?BT_SPEAKER_MAC is not set}"

connected() { bluetoothctl info "$BT_SPEAKER_MAC" 2>/dev/null | grep -q 'Connected: yes'; }

if ! bluetoothctl info "$BT_SPEAKER_MAC" &>/dev/null; then
  logger -t loft-bt-speaker "${BT_SPEAKER_MAC} is not paired"
  exit 0
fi
connected && exit 0

bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' || bluetoothctl power on > /dev/null 2>&1
bluetoothctl --timeout 15 connect "$BT_SPEAKER_MAC" > /dev/null 2>&1
connected && logger -t loft-bt-speaker "connected ${BT_SPEAKER_MAC}"
exit 0
