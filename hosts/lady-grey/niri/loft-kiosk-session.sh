#!/usr/bin/env bash
# loft-kiosk-session — greetd's autologin command. Restarts niri whenever it
# exits (crash or Mod+Shift+E) so the panel never stops at a login prompt.
# Administer over SSH; `sudo systemctl stop greetd` ends the loop.
while true; do
  /usr/local/bin/niri-session
  sleep 2
done
