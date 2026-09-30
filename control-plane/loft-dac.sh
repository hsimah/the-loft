#!/usr/bin/env bash
# loft-dac.sh — keep a USB DAC awake and set its hardware volume.
#
# Installed by the kiosk bootstrap to /usr/local/bin/loft-dac and run by
# loft-dac.service whenever udev sees the card (boot and replug). Config from
# /etc/default/loft-dac: AUDIO_CARD (ALSA card name, e.g. "Audio"),
# AUDIO_CONTROL (mixer control, e.g. "PCM"), AUDIO_VOLUME (e.g. "80%").
#
# The card is found by name, not index or USB ID, so the same script works on
# any kiosk. Snapclient closes the PCM between streams, and USB runtime PM then
# suspends the DAC, costing a pop or clipped start; the card also powers up at
# ~50%, and alsa-restore only replays whatever was saved at shutdown.
set -euo pipefail

: "${AUDIO_CARD:?AUDIO_CARD is not set}"
: "${AUDIO_CONTROL:=PCM}"
: "${AUDIO_VOLUME:?AUDIO_VOLUME is not set}"

card=""
for id in /sys/class/sound/card*/id; do
  if [[ "$(<"$id")" == "$AUDIO_CARD" ]]; then
    card="$(dirname "$id")"
    break
  fi
done
if [[ -z "$card" ]]; then
  echo "loft-dac: card '${AUDIO_CARD}' not present" >&2
  exit 0
fi

# A USB sound card's device is the USB interface; its parent is the USB device
# that owns the runtime power setting.
power="$(dirname "$(readlink -f "${card}/device")")/power/control"
if [[ -w "$power" ]]; then
  echo on > "$power"
  echo "loft-dac: runtime suspend disabled ($power)"
fi

amixer -q -c "$AUDIO_CARD" sset "$AUDIO_CONTROL" "$AUDIO_VOLUME" unmute
# Save it so alsa-restore can't put an older level back.
alsactl store "$AUDIO_CARD" 2>/dev/null || true
echo "loft-dac: ${AUDIO_CARD}/${AUDIO_CONTROL} set to ${AUDIO_VOLUME}"
