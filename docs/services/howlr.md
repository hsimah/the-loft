# Howlr — whole-home audio

[Compose](../../services/howlr/docker-compose.yml) profiles: `server` runs Music Assistant (`howlr`) on space-needle; `client` runs Snapclient (`howlr-snapclient`) on Calavera and Woodstock. Both use host networking. MA embeds Snapcast (1704/1705/1780) and serves its UI on 8095. Caddy routes `howlr.loft.hsimah.com` and `snapweb.loft.hsimah.com`.

## Configuration

[.env.example](../../services/howlr/.env.example). Server: `COMPOSE_PROFILES=server`; providers, users and groups live in `/opt/howlr` and are set in MA's UI (not in Git). Clients: `client`, `SNAPSERVER_HOST`, `SOUND_DEVICE`, stable `HOST_ID`; device details are on the host pages.

| Group | Players |
|---|---|
| Downstairs | Calavera |
| Upstairs | Woodstock |
| All | both |

The kiosks' display-power daemon keys off Snapcast stream IDs in each host.conf; recheck them after changing groups.

## Spotify

Two Spotify provider instances, one per person (same Premium Family plan), using Soloist as the playback engine (one active player per account). Each user sees only their own via MA's per-user **provider_filter** allowlist (Settings → Users). AirPlay Receiver and Spotify Connect are disabled.

- **Deleting a provider removes it from every user's allowlist**, and the replacement gets a new ID that isn't added. It loads fine but is invisible in Browse, with no errors. After re-adding any provider, recheck Settings → Users.
- Premium is only checked at authorization. A "needs Premium" error on re-add usually means the browser authorized the wrong account, not an MA bug.

## Operations

```bash
loft-ctl rebuild howlr
loft-ctl health howlr
sudo docker logs howlr-snapclient --tail 50   # on a client
```

Verify actual playback, not just the UI. Back up `/opt/howlr` before server upgrades.

- **Connected but silent**: ALSA device, DAC power/mixer, MA queue, client logs.
- **Missing player after recreation**: check `HOST_ID` against the UI; remove orphans only once the replacement works.
