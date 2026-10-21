# Howlr — whole-home audio

[Compose](../../services/howlr/docker-compose.yml) profiles: `server` runs Music Assistant (`howlr`) on space-needle; `client` runs Snapclient (`howlr-snapclient`) on Calavera, Woodstock and Fjord. Fjord builds its own image to play to a Bluetooth speaker; see [Fjord audio](../hosts/fjord.md#audio). Both use host networking. MA embeds Snapcast (1704/1705/1780) and serves its UI on 8095. Caddy routes `howlr.loft.hsimah.com` and `snapweb.loft.hsimah.com`.

## Configuration

[.env.example](../../services/howlr/.env.example). Server: `COMPOSE_PROFILES=server`; providers, users and groups live in `/opt/howlr` and are set in MA's UI (not in Git). Clients: `client`, `SNAPSERVER_HOST`, `SOUND_DEVICE`, stable `HOST_ID`, `SNAPCLIENT_VOLUME`; device details are on the host pages.

On clients, `setup.sh` installs `loft-snapclient-volume.service` ([script](../../services/howlr/snapclient-volume.sh)). Once per boot it sets the client's Snapcast volume to `SNAPCLIENT_VOLUME` (default 75), retrying until Snapserver knows the client; MA owns the volume afterwards. It reads `.env` at run time, so edits apply on the next boot. Setup only enables it; to apply now: `sudo systemctl start loft-snapclient-volume`.

| Group | Players | Stream ID |
|---|---|---|
| Downstairs | Calavera | `syncgroupbkmvcshl` |
| Upstairs | Woodstock, Fjord | `syncgroup28jexljs` |
| Sun Room | Woodstock | `syncgroupbtwnba74` |
| Master Bedroom | Fjord | `syncgroupk9axnam5` |
| All | Calavera, Woodstock, Fjord | `syncgroupzewbtz9n` |

Stream IDs are Snapserver's `Music Assistant - <MA player ID without underscores>`. MA creates a group's stream on its first play; list them with:

```bash
curl -s https://snapweb.loft.hsimah.com/jsonrpc -d '{"id":1,"jsonrpc":"2.0","method":"Server.GetStatus"}' | jq -r '.result.server.streams[] | "\(.id)\t\(.status)"'
```

The kiosks' display-power daemon keys off Snapcast stream IDs in each host.conf; recheck them after changing groups. A new group that contains a kiosk needs its stream ID added to that kiosk's `I3_POWER_GROUPS`.

## Spotify

Two Spotify provider instances, one per person (same Premium Family plan), using Soloist as the playback engine (one active player per account). Each user sees only their own via MA's per-user **provider_filter** allowlist (Settings → Users). AirPlay Receiver and Spotify Connect are disabled.

- **Deleting a provider removes it from every user's allowlist**, and the replacement gets a new ID that isn't added. It loads fine but is invisible in Browse, with no errors. After re-adding any provider, recheck Settings → Users.
- Premium is only checked at authorization. A "needs Premium" error on re-add usually means the browser authorized the wrong account, not an MA bug.

## Operations

```bash
loft-ctl rebuild howlr
loft-ctl health howlr
sudo docker logs howlr-snapclient --tail 50   # on a client
journalctl -u loft-snapclient-volume -b       # boot volume, on a client
```

Verify actual playback, not just the UI. Back up `/opt/howlr` before server upgrades.

- **Connected but silent**: ALSA device, DAC power/mixer, MA queue, client logs.
- **"You do not have permission to perform this action"** on a player or group: new players are not added to users' allowed players. Add them in Settings → Users.
- **Missing player after recreation**: check `HOST_ID` against the UI; remove orphans only once the replacement works.
