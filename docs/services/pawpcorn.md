# Pawpcorn — Plex

[Compose](../../services/pawpcorn/docker-compose.yml) runs Plex on space-needle with host networking (32400), `/dev/dri` passthrough and libraries from `/mammoth/library`. `https://pawpcorn.loft.hsimah.com` or `http://192.168.86.28:32400/web`.

## Configuration and data

[.env.example](../../services/pawpcorn/.env.example). The example's `PLEX_UID`/`PLEX_GID` are 1004/1003, but fresh setup makes littledog 1003; check `id littledog` and existing ownership before choosing.

- `/opt/pawpcorn/config`: DB, metadata, watch state.
- `/mammoth/pawpcorn/transcode`: scratch.
- `/mammoth/library/*` mounted under `/data`.

First claim needs a fresh `PLEX_CLAIM` from [plex.tv/claim](https://plex.tv/claim). Don't delete Preferences.xml to fix claim problems.

## Operations

```bash
loft-ctl rebuild pawpcorn
loft-ctl health pawpcorn
sudo docker exec pawpcorn ls -ln /dev/dri
```

Back up the config dir before changing the pin. Verify libraries, direct play and a hardware transcode after upgrade; migrations can outlast the health window.

Hardware transcoding needs Plex Pass and the Plex process's in-container access to `/dev/dri`; host group membership alone doesn't prove it. Remote Access/relay state is configured in Plex, not here.
