# Mercurius — household wiki and documents

[Compose](../../services/mercurius/docker-compose.yml) runs the household wiki and document archive on space-needle, all on one encrypted volume. [SilverBullet](https://docs.silverbullet.md) (`silverbullet`) holds plans, trips, places, projects, lists and notes about documents as plain markdown. [Paperless-ngx](https://docs.paperless-ngx.com) (`paperless`) stores financial, medical and personal records, with Postgres (`mercurius-db`), Valkey (`mercurius-redis`), and Gotenberg and Tika (`mercurius-gotenberg`, `mercurius-tika`) for email and office files. Named for the Roman god of commerce and communication, and the planet Mercury. Plan and later work: [automation plans](../../automation/plans/mercurius.md).

Deployed on space-needle 2026-10-29, replacing the separate Plutus and wiki-only Mercurius; egress probes confirmed. The old wiki folder and Forgejo repo await [cleanup](../../automation/plans/mercurius.md#migration).

| Path | Contents |
|---|---|
| `/dev/ubuntu-vg/mercurius` | 250 GB LVM volume on the NVMe, LUKS2 |
| `/mercurius` | The unlocked volume (XFS): Paperless's `data`, `media` (originals and archived PDFs), `consume`, `export`, `db`, `redis`; `gpt` (paperless-gpt's `config`, `db`, `prompts`); `silverbullet` (SilverBullet's data folder) |

Everything the group stores, including Postgres with the OCR text and every wiki page, is on the encrypted volume. Its directories are created only by [mercurius-vault.sh](../../control-plane/mercurius-vault.sh) after it has confirmed `/mercurius` is the vault, never by setup. The wiki may hold anything, including amounts, document details and OCR text.

## Isolation

- **Locked means down.** Every bind uses `create_host_path: false`. With the vault locked, `/mercurius` is an empty directory on the root disk and Docker refuses to start the group. It cannot initialise an empty archive or wiki there. `setup.sh` skips Mercurius until the mount exists (`SERVICE_REQUIRES_MOUNT` in [host.conf](../../hosts/space-needle/host.conf)).
- **No route out.** The group's own network and `mercurius-proxy` are both Docker `internal` networks. `mercurius-proxy` is shared only with Caddy, through space-needle's [Mushr override](../../hosts/space-needle/overrides/mushr/docker-compose.override.yml). Nothing in the group is on `loft-proxy`. The one exception is Paperless and paperless-gpt, which may reach llama-swap on helarctos and nothing else ([model egress](#model-egress)).
- **SilverBullet has no route out.** `SB_SHELL_BACKEND=off` disables the server shell for every space, and the `-slim` image has no Runtime API. The HTTP proxy (`net.proxyFetch`) reaches only the group's internal network, where Paperless is `http://paperless:8000`. Libraries and plugs that fetch from the internet cannot be installed.
- **Access.** `https://wiki.loft.hsimah.com` and `https://paperless.loft.hsimah.com`, LAN only; never on the tunnel.

## Accounts

- **SilverBullet:** one account each, both with `write` on the `home` space. In SilverBullet, `write` includes authoring Space Lua that runs in the other person's browser, so only trusted people get it.
- **Paperless:** one shared archive with an account each, both superusers: owners otherwise hide documents from each other, and either superuser can reset the other's password or two-factor. Enable two-factor authentication on both (Profile → Two-factor authentication).

## After every reboot

The vault stays locked until unlocked by hand; `loft-ctl health` reports `wiki` and `paperless` down until then.

```bash
sudo control-plane/mercurius-vault.sh unlock
loft-ctl start mercurius
```

`mercurius-vault.sh status` reports the state. To lock: `loft-ctl stop mercurius`, then `sudo control-plane/mercurius-vault.sh lock`.

## Create the volume (once)

Run from `/srv/the-loft`, one at a time:

1. `sudo lvcreate -L 250G -n mercurius ubuntu-vg`
2. `sudo cryptsetup luksFormat --type luks2 /dev/ubuntu-vg/mercurius`. Use a long passphrase and store it in the password manager.
3. `sudo cryptsetup luksAddKey /dev/ubuntu-vg/mercurius`: a second, recovery passphrase (`openssl rand -base64 30`) for the printed recovery sheet in the safe ([backups plan](../../automation/plans/backups.md#key-custody-d11)).
4. `sudo cryptsetup luksHeaderBackup /dev/ubuntu-vg/mercurius --header-backup-file /root/mercurius-luks-header.img`. A damaged header makes the volume unrecoverable even with the passphrase. Copy it to the USB stick in the safe, then `sudo shred -u` it on the host: with either passphrase it opens the vault. Renaming the LV does not change the header, so the `plutus-luks-header.img` already in the safe is still this volume's.
5. `sudo cryptsetup open /dev/ubuntu-vg/mercurius mercurius`, then `sudo mkfs.xfs -L mercurius /dev/mapper/mercurius`.
6. `sudo control-plane/mercurius-vault.sh unlock` mounts it and creates the directories.

Grow it later while it is online: `lvextend`, `cryptsetup resize mercurius`, then `xfs_growfs /mercurius`.

## Setup

1. Copy [.env.example](../../services/mercurius/.env.example) and generate `DB_PASSWORD` and `PAPERLESS_SECRET_KEY` with `openssl rand -hex 32` **before** the first start.
2. `sudo bash setup.sh` creates the `mercurius-proxy` and `mercurius-llm` networks and installs the egress firewall. Then `loft-ctl start mushr` recreates Caddy on `mercurius-proxy`.
3. With the vault unlocked: `loft-ctl start mercurius`, then `loft-ctl health mercurius`.
4. Paperless: open `https://paperless.loft.hsimah.com` and create the first account, which becomes the superuser. Create the second under Settings → Users & Groups as a superuser too, and turn on two-factor for both.
5. SilverBullet: open `https://wiki.loft.hsimah.com`. The setup wizard creates the first admin account, then the first space: name it `home`, bound to `wiki.loft.hsimah.com` at `/`. In the dashboard, create the second account and add it to `home` with `write`; set each account's full name and email, which revisions are attributed to. Turn on revisions in **Managed** mode, with no remote.
6. Confirm the way out is only the model route ([model egress](#model-egress)).

## Wiki revisions

Each space's history is a git repository in its folder on the vault, managed by SilverBullet, with no remote ([docs](https://docs.silverbullet.md/Revisions)). SilverBullet commits about 30 seconds after editing stops. Browse and restore pages with the `Revisions: *` commands. The history is only as safe as the vault: until [backups](#backups) return it is one copy.

## Model egress

Paperless (`paperless`) and [paperless-gpt](https://github.com/icereed/paperless-gpt) (`paperless-gpt`, profile `ocr`) are the only Mercurius containers with a route out, and the route reaches llama-swap on helarctos (`192.168.86.21:8080`) and nothing else. SilverBullet, the database, Valkey, Gotenberg and Tika stay on internal networks.

- **Bridge:** `mercurius-llm`, created by setup.sh with a fixed bridge name. Both containers also stay on the group's internal network, where Paperless is `http://paperless:8000`.
- **Firewall:** [mercurius-egress.nft](../../hosts/space-needle/mercurius-egress.nft) allows that one address and port from the bridge and drops everything else, including DNS, IPv6 and traffic to space-needle itself. [loft-mercurius-egress.service](../../hosts/space-needle/loft-mercurius-egress.service) loads it before Docker starts; space-needle's [bootstrap](../../hosts/space-needle/bootstrap) installs both. It owns one nft table and never flushes Docker's rules.
- **Start order:** the group references the external `mercurius-llm` bridge, so run `sudo bash setup.sh` (which creates it) before `loft-ctl start mercurius`.
- **No DNS:** `helarctos` resolves through `extra_hosts`, pinned to the address the firewall allows. If helarctos's address changes, change both.
- **No login:** paperless-gpt has none, so it has no Caddy route. Its page listens on `127.0.0.1:8081`; reach it with `ssh -L 8081:localhost:8081 adminhabl@space-needle`.

Probe with the profile running. The two `/health` calls must answer and the others must fail, by refusal or timeout:

```bash
sudo docker exec paperless-gpt wget -T 5 -qO- http://192.168.86.21:8080/health
sudo docker exec paperless-gpt wget -T 5 -qO- http://192.168.86.28
sudo docker exec paperless-gpt wget -T 5 -qO- http://1.1.1.1
sudo docker exec paperless curl -sS -m 5 http://192.168.86.21:8080/health
sudo docker exec paperless curl -sS -m 5 http://1.1.1.1
```

## Second-pass OCR

Paperless ingests every document as it arrives and keeps what it extracts: a PDF's embedded text layer, or Tesseract's reading of a scan. A second pass is on demand, for documents whose text is bad (older PDFs, odd layouts, poor scans): tag the document `paperless-gpt-ocr-auto` (bulk edit works for many). paperless-gpt then reads it again with a vision model on helarctos: it polls Paperless's API for documents carrying the tag, renders each page, sends it to `glm-ocr` at temperature 0, and writes the recognised text back. Two independent readings let a later job flag documents where they disagree ([plan](../../automation/plans/documents.md#scanning-ocr-and-re-checking)). paperless-gpt's own suggestions (titles, tags) are off; Paperless's [built-in AI](#built-in-ai) does that.

Settings are in [Compose](../../services/mercurius/docker-compose.yml). `glm-ocr` and `paddleocr-vl` expect fixed task prompts (`Text Recognition:` and `OCR:`), so set `ocr_prompt.tmpl` to the one for the model in use. One page at a time goes in as an image, which is how the models skipped regions in [the first test](../../automation/plans/models.md#household-roster).

Set up, one step at a time, after the model egress is installed:

1. With the vault unlocked, `sudo control-plane/mercurius-vault.sh unlock` creates `/mercurius/gpt`.
2. In Paperless, create an API token (admin → Auth Tokens) and a tag `paperless-gpt-ocr-auto`. Put the token, helarctos's `LLAMA_SWAP_API_KEY` and `COMPOSE_PROFILES=ocr` in Mercurius's `.env`, then `loft-ctl start mercurius`.
3. Run the probes above.
4. Replace the OCR prompt: `printf 'Text Recognition:' | sudo tee /mercurius/gpt/prompts/ocr_prompt.tmpl`, then restart `paperless-gpt`. The default prompt gives the model Paperless's Tesseract text and asks it to correct it, which anchors the second reading on the first and defeats the comparison; the plain task prompt gives it the page image alone.
5. Try it on a non-sensitive document: tag it by hand and confirm what changes in its content. No workflow tags new documents, so nothing is re-read unless you ask. Leave `OCR_SKIP_DIGITAL_PAGES` off: with it on, a pass on a born-digital PDF may skip pages it judges to have a clean text layer.

paperless-gpt's `db` holds a run log and undo history.

## Built-in AI

Paperless's own AI is enabled in [Compose](../../services/mercurius/docker-compose.yml) and points at llama-swap (`PAPERLESS_AI_*`): suggestions on a document, chat, and similar documents. Not yet tried on 3.3.4.

- **Chat and suggestions:** `qwen3.6-35b-a3b`. It is not resident: the first request after a swap waits 23–36 s while it loads, and it evicts whichever large model is running, including a coding job's. The request timeout is 300 s. Which model stays resident is D18 ([models](../../automation/plans/models.md#sharing-the-gpu)).
- **Similar documents:** `embeddinggemma`, always loaded. Paperless indexes every document daily (`PAPERLESS_LLM_INDEX_TASK_CRON`, default 02:10), so the first run on a full archive is long; add the variable to Compose to move it.
- **Key:** helarctos's `LLAMA_SWAP_API_KEY` in Mercurius's `.env`. Without it, AI requests fail with 401.
- **What leaves:** document text goes to helarctos over the LAN, as plain HTTP, for each request. It is held in memory there and not logged: after a real ID document went through, the container logs of llama-swap (helarctos), Paperless and paperless-gpt held no document text or image data. After the bulk second-pass OCR, paperless-gpt's log held large serialized text, probably document text; not yet checked ([plan](../../automation/plans/documents.md#llm-improvements)). Recheck after changing llama-swap's `logLevel`; its in-memory `/logs` buffer is not on disk and clears when the container is recreated.
- **Models:** fetch commands are under [Paperless models](sputnik.md#paperless-models).

## Bulk import

The consume folder is recursive, and each folder on a document's path becomes a tag (`consume/Tax/2019/w2.pdf` gets `Tax` and `2019`). Tags are flat: a folder name used in more than one branch becomes one shared tag. The filename becomes the title. After an import, move institution tags to correspondents with [paperless-tag-to-correspondent.sh](../../control-plane/paperless-tag-to-correspondent.sh) (`--dry-run` first; the correspondents must exist), then delete those tags and the ones that only carried the folder layout (years, `Documents`). Deleting a tag leaves its documents in place; wait until paperless-gpt has no documents queued, since it rewrites tag lists.

- Copy with `sudo rsync -rt --chown=1003:1003 <src>/ /mercurius/consume/`. rsync writes each file under a temporary name and renames it into place, so Paperless never reads a half-copied file. Paperless deletes each file once it has been consumed, so it needs ownership.
- Only files with a supported extension are consumed; files without one are skipped, and Paperless does not unpack zips.
- Paperless rejects a duplicate (same checksum) as a failed task; failures are listed under Tasks.
- Documents from the consume folder have no owner, so both accounts can see them.
- The source tree is plaintext outside the vault, but with no [backup](#backups) it is also the second copy. Delete it once the import is checked and the documents exist elsewhere (paper or OneDrive).

## Backups

None running. One vault job (Paperless's `document_exporter` output, a Postgres dump and the SilverBullet folder with its revisions, into a restic repository on Google Drive) is [built but shelved](../operations/backups.md), so the vault is one copy on one disk: keep paper originals.

## Upgrades

- **Paperless and Postgres** migrate one way. Run `document_exporter` and `pg_dump` first and read [upgrades](../operations/upgrades.md). The Postgres major (18) moves only with a dump and restore.
- **SilverBullet:** pin the `-slim` version tag. After an upgrade, reload the browser twice so the service worker picks up the new client.

## Troubleshooting

- **`bind source path does not exist: /mercurius/...`**: the vault is locked. Unlock it, then start the group.
- **`mercurius-vault.sh` says another device is mounted**: something else is on `/mercurius`; unmount it. The script never creates directories there.
- **502 from Caddy**: the group is stopped, or Mushr was not recreated after `mercurius-proxy` was created (`sudo docker inspect mushr` should list both networks).
- **`mercurius-db` logs `cannot create directory '/var/lib/postgresql'`**: `/mercurius/db` is not traversable; it must be `755` (Postgres 18 only chowns its `18/docker` subdirectory).
- **Database authentication fails at start**: `DB_PASSWORD` changed after the cluster was initialised. Fix it with `ALTER ROLE` inside `mercurius-db`.
- **Paperless two-factor activation returns `{"success":false}`**: the code didn't match the secret. Paperless makes a new secret each time the dialog opens; delete the authenticator entry, open the dialog once, scan, and enter the code at once.
- **Wiki space not found or redirects to the dashboard**: the space is bound to a different hostname than the one in the browser.
- **Every wiki request redirects to another hostname**, so the dashboard is unreachable: `primaryUrl` in `/mercurius/silverbullet/server.json` names it. `sudo docker stop silverbullet`, fix the line with `sudo nano` (which keeps littledog as owner; `sed -i` would not), then start it.
- **SilverBullet logs `boot mode: single-space`**: a legacy `SB_*` variable is set, or `/mercurius/silverbullet` held files before the first boot. Multi-space setup only runs on an empty data folder with no legacy variables.
