#!/usr/bin/env bash
# snapclient-volume.sh — set this client's Snapcast volume once per boot.
# Installed by services/howlr/setup.sh to /usr/local/bin/loft-snapclient-volume
# and run by loft-snapclient-volume.service, so each client boots at
# SNAPCLIENT_VOLUME and MA can change it freely afterwards. Settings come from
# the Howlr .env named by HOWLR_ENV, read at run time, so .env edits apply on
# the next boot without re-running setup.
#
# Snapcast's client id is snapclient's --hostID. Snapserver keeps a known
# client's volume while it is offline and sends it on connect, so start order
# against snapclient doesn't matter. A client the server has never seen is
# refused ("Client not found") and retried until it first connects.
set -uo pipefail

SNAP_HOST="${SNAPSERVER_HOST:-}"
SNAP_PORT="${SNAPSERVER_CONTROL_PORT:-1705}"
CLIENT_ID="${HOST_ID:-}"
VOLUME="${SNAPCLIENT_VOLUME:-75}"
REPLY_SECS=5
RETRY_MAX_SECS=30

log() { printf '%s\n' "$*"; }

# Value of KEY in a Compose .env: last assignment wins, an unquoted value ends
# at whitespace + "#", and one pair of surrounding quotes is removed.
env_value() { # key file
  local line
  line="$(grep -E "^[[:space:]]*$1=" "$2" | tail -n 1)"
  [[ -n "$line" ]] || return 1
  line="${line#*=}"
  if [[ "$line" =~ ^\"([^\"]*)\" || "$line" =~ ^\'([^\']*)\' ]]; then
    line="${BASH_REMATCH[1]}"
  else
    line="${line%%[[:space:]]#*}"
    line="${line%"${line##*[![:space:]]}"}"
  fi
  printf '%s' "$line"
}

load_env() { # file
  [[ -r "$1" ]] || { log "ERROR: cannot read ${1}"; return 1; }
  SNAP_HOST="$(env_value SNAPSERVER_HOST "$1")"
  CLIENT_ID="$(env_value HOST_ID "$1")"
  VOLUME="$(env_value SNAPCLIENT_VOLUME "$1")" || VOLUME=75
}

valid_config() {
  [[ -n "$SNAP_HOST" ]] || { log "ERROR: SNAPSERVER_HOST is empty"; return 1; }
  [[ -n "$CLIENT_ID" ]] || { log "ERROR: HOST_ID is empty"; return 1; }
  [[ "$VOLUME" =~ ^[0-9]+$ ]] && (( 10#$VOLUME <= 100 )) \
    || { log "ERROR: SNAPCLIENT_VOLUME must be 0-100, got '${VOLUME}'"; return 1; }
}

volume_request() { # client-id percent
  printf '{"id":1,"jsonrpc":"2.0","method":"Client.SetVolume","params":{"id":"%s","volume":{"muted":false,"percent":%d}}}\n' \
    "$1" "$((10#$2))"
}

# Send the request and wait for its reply, skipping notifications (no
# numeric id) that Snapserver pushes to every control connection.
set_volume() { # in-fd out-fd
  local in="$1" out="$2" line
  volume_request "$CLIENT_ID" "$VOLUME" >&"$out" || return 1
  while IFS= read -r -t "$REPLY_SECS" -u "$in" line; do
    [[ "$line" =~ \"id\":1[,}] ]] || continue
    if [[ "$line" == *'"error"'* ]]; then
      log "snapserver refused: ${line}"
      return 1
    fi
    return 0
  done
  log "no reply from ${SNAP_HOST}:${SNAP_PORT}"
  return 1
}

main() {
  local backoff=1
  if [[ -n "${HOWLR_ENV:-}" ]]; then
    load_env "$HOWLR_ENV" || exit 1
  fi
  valid_config || exit 1
  while true; do
    if exec 3<> "/dev/tcp/${SNAP_HOST}/${SNAP_PORT}"; then
      if set_volume 3 3; then
        exec 3>&-
        log "${CLIENT_ID} volume set to $((10#$VOLUME))%"
        return 0
      fi
      exec 3>&-
    else
      log "cannot reach ${SNAP_HOST}:${SNAP_PORT}"
    fi
    log "retrying in ${backoff}s"
    sleep "$backoff"
    backoff=$(( backoff * 2 > RETRY_MAX_SECS ? RETRY_MAX_SECS : backoff * 2 ))
  done
}

# Sourcing (tests) defines the functions without connecting.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main
fi
