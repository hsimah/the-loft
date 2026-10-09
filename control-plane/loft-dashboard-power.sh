#!/usr/bin/env bash
# loft-dashboard-power.sh — kiosk screen power for the i3 dashboard hosts
# (Calavera, Woodstock). The Surface bootstrap installs it as
# /usr/local/bin/loft-dashboard-power; host config comes from
# /etc/default/loft-dashboard-power (LOFT_POWER_GROUPS from host.conf's
# I3_POWER_GROUPS).
#
# Wakes the display the moment a watched Music Assistant sync group plays, and
# blanks it after LOFT_POWER_IDLE_SECS with no playback AND no local input
# (xprintidle), so it doesn't blank while someone browses between tracks.
#
# Talks to Snapserver's JSON-RPC control API over plain TCP (newline-delimited,
# port 1705), the same protocol Snapweb uses over WebSocket. Music Assistant's
# own WebSocket never delivered player events to a plain client; Snapserver
# pushes Stream.OnProperties to any connected client with no handshake. A
# group's stream id is "Music Assistant - <queue_id without underscores>"
# (MA "syncgroup_bkmvcshl" -> "Music Assistant - syncgroupbkmvcshl");
# LOFT_POWER_GROUPS holds that stripped form, read from Snapweb or
# Server.GetStatus, since the transform isn't documented.
set -uo pipefail

SNAP_HOST="${LOFT_POWER_SNAP_HOST:-192.168.86.28}"
SNAP_PORT="${LOFT_POWER_SNAP_PORT:-1705}"
IDLE_SECS="${LOFT_POWER_IDLE_SECS:-600}"
POLL_SECS=15
RECONNECT_MAX_SECS=30
STREAM_PREFIX="Music Assistant - "

declare -A STATES=()
IFS=',' read -ra _groups <<< "${LOFT_POWER_GROUPS:-}"
for _g in "${_groups[@]}"; do
  _g="${_g//[[:space:]]/}"
  [[ -z "$_g" ]] || STATES["$_g"]=idle
done
unset _g _groups

log() { printf '%s\n' "$*"; }

# "On", "Off", "Standby" or "Suspend" from X, or nothing when unknown. Ask X
# every time: a touch wakes the panel without telling us.
monitor_state() {
  xset q 2> /dev/null | sed -n 's/^[[:space:]]*Monitor is //p' | head -1
}

set_screen() { # on|off
  local state
  state="$(monitor_state)"
  if [[ "$1" == on && "$state" == On ]] || [[ "$1" == off && -n "$state" && "$state" != On ]]; then
    return 0
  fi
  if xset dpms force "$1"; then
    log "screen $1"
  else
    log "ERROR: xset dpms force $1 failed"
  fi
}

is_streaming() {
  local g
  for g in "${!STATES[@]}"; do
    [[ "${STATES[$g]}" == playing ]] && return 0
  done
  return 1
}

IDLE_FAILING=false
idle_check() {
  is_streaming && return 0
  local idle
  if ! idle="$(xprintidle 2> /dev/null)" || [[ ! "$idle" =~ ^[0-9]+$ ]]; then
    # Unknown idle time never blanks, but say so once instead of staying silent.
    $IDLE_FAILING || log "ERROR: xprintidle failed; not blanking until it recovers"
    IDLE_FAILING=true
    return 0
  fi
  if $IDLE_FAILING; then log "xprintidle recovered"; IDLE_FAILING=false; fi
  (( idle >= IDLE_SECS * 1000 )) && set_screen off
  return 0
}

# Apply one JSON-RPC message: a Stream.OnProperties notification, or the
# Server.GetStatus reply that seeds every stream's state on (re)connect.
handle_message() { # json-line
  local id state group
  while IFS=$'\t' read -r id state; do
    group="${id#"$STREAM_PREFIX"}"
    [[ "$id" == "$STREAM_PREFIX"* && -n "${STATES[$group]+set}" ]] || continue
    if [[ "${STATES[$group]}" != "$state" ]]; then log "${group} -> ${state}"; fi
    STATES["$group"]="$state"
    [[ "$state" == playing ]] && set_screen on
  done < <(jq -r '
    if .method == "Stream.OnProperties" then [.params.id, (.params.properties.playbackStatus // "")]
    elif (.result.server.streams? | type) == "array" then
      .result.server.streams[] | [.id, (.properties.playbackStatus // .status // "")]
    else empty end | @tsv' <<< "$1" 2> /dev/null)
}

# Read messages from one connection until it closes, polling idle every
# POLL_SECS. A read that times out mid-line keeps its partial input.
session() { # in-fd out-fd
  local in="$1" out="$2" line partial="" last=$SECONDS wait status
  printf '%s\n' '{"id":1,"jsonrpc":"2.0","method":"Server.GetStatus"}' >&"$out"
  while true; do
    wait=$(( POLL_SECS - (SECONDS - last) ))
    (( wait < 1 )) && wait=1
    if IFS= read -r -t "$wait" -u "$in" line; then
      handle_message "${partial}${line}"
      partial=""
    else
      status=$?
      (( status > 128 )) || return 0
      partial+="$line"
    fi
    if (( SECONDS - last >= POLL_SECS )); then
      idle_check
      last=$SECONDS
    fi
  done
}

main() {
  local groups backoff=1
  groups="$(printf '%s\n' "${!STATES[@]}" | sort | paste -sd, -)"
  if [[ -z "$groups" ]]; then
    log "WARNING: LOFT_POWER_GROUPS is empty; the screen will blank on idle but never wake on playback"
  fi
  while true; do
    if exec 3<> "/dev/tcp/${SNAP_HOST}/${SNAP_PORT}"; then
      log "connected to ${SNAP_HOST}:${SNAP_PORT}, watching groups: ${groups:-(none configured)}"
      backoff=1
      session 3 3
      exec 3>&-
      log "connection lost, retrying in ${backoff}s"
    else
      log "cannot reach ${SNAP_HOST}:${SNAP_PORT}, retrying in ${backoff}s"
    fi
    sleep "$backoff"
    idle_check
    backoff=$(( backoff * 2 > RECONNECT_MAX_SECS ? RECONNECT_MAX_SECS : backoff * 2 ))
  done
}

# Sourcing (tests) defines the functions without connecting.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main
fi
