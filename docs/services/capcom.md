# Capcom — Home Assistant

[Compose](../../services/capcom/docker-compose.yml) runs Home Assistant (`capcom`) on space-needle with host networking, so discovery and LAN integrations work. It listens on 8123. Caddy routes `capcom.loft.hsimah.com` (LAN only; never on the tunnel). [Lady Grey](../hosts/lady-grey.md) is its wall tablet.

Live on space-needle; onboarded.

## Configuration

`/opt/capcom/config` holds everything: `configuration.yaml`, `.storage` (users, integrations, dashboards) and the recorder database. Integrations, users and dashboards are set in the UI, not in Git.

Home Assistant rejects proxied requests with 400 until Caddy is trusted. HTTP settings live in `.storage/http` (UI: Settings → System → Network → HTTP server); a YAML `http:` block is imported only before the first start and is deprecated, so do not use one. Caddy arrives from its Docker bridge address. On a fresh config, after the first start:

```bash
f=/opt/capcom/config/.storage/http
sudo docker stop capcom && sudo cp "$f" "$f.bak"
sudo jq '.data.stable += {use_x_forwarded_for: true, trusted_proxies: ["172.16.0.0/12"]}' "$f.bak" | sudo tee "$f" >/dev/null
sudo docker start capcom
```

Then onboard at `https://capcom.loft.hsimah.com` and create a non-admin user for each kiosk. If the browser shows `ERR_FAILED` after login, clear the site's data: a service worker cached from the 400s. USB radios (Zigbee, Z-Wave) need a `devices:` entry in Compose. Bluetooth uses the host's BlueZ through `/run/dbus`.

```bash
sudo docker logs capcom --tail 50
curl -s -o /dev/null -w '%{http_code}\n' https://capcom.loft.hsimah.com/manifest.json
```

## Upgrades

Monthly releases migrate the recorder database and do not support downgrades. Stop it and archive `/opt/capcom/config` before changing the tag ([upgrades](../operations/upgrades.md)).
