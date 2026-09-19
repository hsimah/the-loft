# Howlr — whole-home audio

[Compose](../../services/howlr/docker-compose.yml) uses `server` for Music Assistant (`howlr`) on space-needle and `client` for Snapcast (`howlr-snapclient`) on Viking/Calavera. Fjord no longer runs audio. Both profiles use host networking.

Music Assistant provides the web UI on 8095 and embedded Snapcast on 1704/1705/1780; there are no separate snapserver, shairport-sync or librespot containers. Caddy routes `https://howlr.loft.hsimah.com` and `https://snapweb.loft.hsimah.com`.

## Configuration

Copy [.env.example](../../services/howlr/.env.example). Server hosts need `COMPOSE_PROFILES=server`; MA's providers/users/groups live in `/opt/howlr` and are configured through its UI. Clients use `client`, `SNAPSERVER_HOST`, `SOUND_DEVICE` and a stable `HOST_ID`. Device settings belong on the [Viking](../hosts/viking.md) and [Calavera](../hosts/calavera.md) pages.

Recorded room layout:

| Player | Host | Group |
|---|---|---|
| `ma_viking` | Viking | Upstairs |
| `ma_calavera` | Calavera | Downstairs |

All spans both. These are UI-managed observations; confirm after reimage or player migration. Calavera's display-power daemon depends on specific stream IDs recorded in its host config.

## Operations

```bash
loft-ctl rebuild howlr
loft-ctl health howlr
# On a client:
sudo docker logs howlr-snapclient --tail 50
```

Verify actual playback, not just the MA login page. Back up `/opt/howlr` before server upgrades; validate providers, room groups, kiosk login and display wake as described in [upgrades](../operations/upgrades.md). New rooms start with the [Pi provisioning guide](../operations/raspberry-pi.md) plus a host manifest.

## Retained operational observations

- **Connected but silent:** verify ALSA device, DAC power/mixer, MA queue and client logs. A down/up can reset stream state, but the historical cross-container FIFO explanation belongs to the retired multi-container stack and is not an established diagnosis for current MA.
- **Missing player after recreation:** check HOST_ID and compare the actual ID with the UI. Remove orphaned players only after confirming the intended replacement.
- **Spotify loads but is absent from Browse:** a recorded provider replacement removed its old instance ID from per-user source allowlists without granting the new one. Review Settings → Users for each affected user, then sync the new provider. Applies to other replaced providers too.
- **Account authorization fails:** verify which account the browser authorized and its entitlement; inspect MA logs. Do not infer entitlement from an old provider's still-working stored token.
- **Recorded account layout:** hsimah used Hamish's Spotify account (Plexamp was the usual path); gemo and calavera shared Georgia's account. Two MA Spotify provider instances used Soloist credentials and phone pairing. AirPlay Receiver/Spotify Connect were disabled. These settings are not encoded in Git and may have changed; check the current UI before rebuilding them from notes.
- **Wi-Fi dropouts:** use the relevant host page; a client connection does not prove uninterrupted stream delivery.
