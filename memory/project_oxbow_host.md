---
name: oxbow host
description: Brisbane Pi+NAS host at Kangaroo Point apartment, used for geo-replication
type: project
---

**Status (2026-09-19): proposed/unverified.** There is no Oxbow host manifest or Syncthing service in this repository. Confirm real-world status before treating this as deployed.

Proposed host `oxbow` — Brisbane apartment at Kangaroo Point, looking over the Gabba and the Brisbane River (the "Big Brown Snake"). Named for the oxbow bend of the river visible from the property.

**Why:** Named per loft conventions (something physically visible). Oxbow bend of Brisbane River wraps around Kangaroo Point.

**How to apply:** Use `oxbow` as the hostname in `hosts/oxbow/host.conf`. The intended role is Syncthing only — dumb file replica of `/mammoth/photos` and `/mammoth/documents` from space-needle. No Immich UI, no Nextcloud.
