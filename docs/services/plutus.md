# Plutus — household vault

[Compose](../../services/plutus/docker-compose.yml) runs [Paperless-ngx](https://docs.paperless-ngx.com) (`plutus`) on space-needle for financial, medical and personal records, with Postgres (`plutus-db`), Valkey (`plutus-redis`), Gotenberg and Tika (`plutus-gotenberg`, `plutus-tika`) for email and office files. Named for the god of wealth and buried ore and gems. Paperless does its own OCR. An optional second pass with the local vision models ([second-pass OCR](#second-pass-ocr)) and Paperless's built-in AI ([AI](#built-in-ai)) are configured and not yet deployed ([plan](../../automation/plans/documents.md)). Deployed on space-needle 2026-10-25 with no route out (egress probe confirmed); the model egress below changes that.

| Path | Contents |
|---|---|
| `/dev/ubuntu-vg/plutus` | 250 GB LVM volume on the NVMe, LUKS2 |
| `/plutus` | The unlocked volume (XFS): `data`, `media` (originals and archived PDFs), `consume`, `export`, `db`, `redis`, and `gpt` (paperless-gpt's `config`, `db`, `prompts`) |

Everything Plutus stores, including Postgres with the OCR text, is on the encrypted volume. Its directories are created only by [plutus-vault.sh](../../control-plane/plutus-vault.sh) after it has confirmed `/plutus` is the vault, never by setup.

## Isolation

- **Locked means down.** Every bind uses `create_host_path: false`. With the vault locked, `/plutus` is an empty directory on the root disk and Docker refuses to start Plutus. It cannot initialise an empty archive there. `setup.sh` skips Plutus until the mount exists (`SERVICE_REQUIRES_MOUNT` in [host.conf](../../hosts/space-needle/host.conf)).
- **No route out.** Plutus's own network and `plutus-proxy` are both Docker `internal` networks. `plutus-proxy` is shared only with Caddy, through space-needle's [Mushr override](../../hosts/space-needle/overrides/mushr/docker-compose.override.yml). Plutus is not on `loft-proxy`. The one exception is Paperless and paperless-gpt, which may reach llama-swap on helarctos and nothing else ([model egress](#model-egress)).
- `https://plutus.loft.hsimah.com`, LAN only; never on the tunnel. One shared archive with an account each; enable two-factor authentication on both (Profile → Two-factor authentication).

## After every reboot

The vault stays locked until unlocked by hand; `loft-ctl health` reports Plutus down until then.

```bash
sudo control-plane/plutus-vault.sh unlock
loft-ctl start plutus
```

`plutus-vault.sh status` reports the state. To lock: `loft-ctl stop plutus`, then `sudo control-plane/plutus-vault.sh lock`.

## Create the volume (once)

Run from `/srv/the-loft`, one at a time:

1. `sudo lvcreate -L 250G -n plutus ubuntu-vg`
2. `sudo cryptsetup luksFormat --type luks2 /dev/ubuntu-vg/plutus`. Use a long passphrase and store it in the password manager.
3. `sudo cryptsetup luksAddKey /dev/ubuntu-vg/plutus`: a second, recovery passphrase (`openssl rand -base64 30`) for the printed recovery sheet in the safe ([backups plan](../../automation/plans/backups.md#key-custody-d11)).
4. `sudo cryptsetup luksHeaderBackup /dev/ubuntu-vg/plutus --header-backup-file /root/plutus-luks-header.img`. A damaged header makes the volume unrecoverable even with the passphrase. Copy it to the USB stick in the safe, then `sudo shred -u` it on the host: with either passphrase it opens the vault.
5. `sudo cryptsetup open /dev/ubuntu-vg/plutus plutus`, then `sudo mkfs.xfs -L plutus /dev/mapper/plutus`.
6. `sudo control-plane/plutus-vault.sh unlock` mounts it and creates the directories.

Grow it later while it is online: `lvextend`, `cryptsetup resize plutus`, then `xfs_growfs /plutus`.

## Setup

1. Copy [.env.example](../../services/plutus/.env.example) and generate `DB_PASSWORD` and `PAPERLESS_SECRET_KEY` with `openssl rand -hex 32` **before** the first start.
2. `sudo bash setup.sh` creates the `plutus-proxy` network. Then `loft-ctl start mushr` recreates Caddy on it.
3. With the vault unlocked: `loft-ctl start plutus`, then `loft-ctl health plutus`.
4. Open `https://plutus.loft.hsimah.com` and create the first account, which becomes the superuser. Create the second account under Settings → Users & Groups as a superuser too: owners otherwise hide documents from each other, and either superuser can reset the other's password or two-factor. Turn on two-factor for both.
5. Confirm the way out is only the model route ([model egress](#model-egress)): `sudo docker exec plutus curl -sS -m 5 https://1.1.1.1` must fail, by refusal (exit 7) or timeout (exit 28), and `http://192.168.86.21:8080/health` must answer.

## Model egress

Paperless (`plutus`) and [paperless-gpt](https://github.com/icereed/paperless-gpt) (`plutus-gpt`, profile `ocr`) are the only Plutus containers with a route out, and the route reaches llama-swap on helarctos (`192.168.86.21:8080`) and nothing else. The database, Valkey, Gotenberg and Tika stay on internal networks.

- **Bridge:** `plutus-llm`, created by setup.sh with a fixed bridge name. The container also stays on Plutus's internal network, where Paperless is `http://plutus:8000`.
- **Firewall:** [plutus-egress.nft](../../hosts/space-needle/plutus-egress.nft) allows that one address and port from the bridge and drops everything else, including DNS, IPv6 and traffic to space-needle itself. [loft-plutus-egress.service](../../hosts/space-needle/loft-plutus-egress.service) loads it before Docker starts; space-needle's [bootstrap](../../hosts/space-needle/bootstrap) installs both. It owns one nft table and never flushes Docker's rules.
- **Start order:** Plutus references the external `plutus-llm` bridge, so run `sudo bash setup.sh` (which creates it) before `loft-ctl start plutus`.
- **No DNS:** `helarctos` resolves through `extra_hosts`, pinned to the address the firewall allows. If helarctos's address changes, change both.
- **No login:** paperless-gpt has none, so it has no Caddy route. Its page listens on `127.0.0.1:8081`; reach it with `ssh -L 8081:localhost:8081 adminhabl@space-needle`.

Probe with the profile running. The two `/health` calls must answer and the other three must fail; the last two run in Paperless's own container:

```bash
sudo docker exec plutus-gpt wget -T 5 -qO- http://192.168.86.21:8080/health
sudo docker exec plutus-gpt wget -T 5 -qO- http://192.168.86.28
sudo docker exec plutus-gpt wget -T 5 -qO- http://1.1.1.1
sudo docker exec plutus curl -sS -m 5 http://192.168.86.21:8080/health
sudo docker exec plutus curl -sS -m 5 http://1.1.1.1
```

## Second-pass OCR

Paperless ingests every document as it arrives and keeps what it extracts: a PDF's embedded text layer, or Tesseract's reading of a scan. A second pass is on demand, for documents whose text is bad (older PDFs, odd layouts, poor scans): tag the document `paperless-gpt-ocr-auto` (bulk edit works for many). paperless-gpt then reads it again with a vision model on helarctos: it polls Paperless's API for documents carrying the tag `paperless-gpt-ocr-auto`, renders each page, sends it to `glm-ocr` at temperature 0, and writes the recognised text back. Two independent readings let a later job flag documents where they disagree ([plan](../../automation/plans/documents.md#scanning-ocr-and-re-checking)). paperless-gpt's own suggestions (titles, tags) are off; Paperless's [built-in AI](#built-in-ai) does that.

Settings are in [Compose](../../services/plutus/docker-compose.yml). `glm-ocr` and `paddleocr-vl` expect fixed task prompts (`Text Recognition:` and `OCR:`), so set `ocr_prompt.tmpl` to the one for the model in use. One page at a time goes in as an image, which is how the models skipped regions in [the first test](../../automation/plans/models.md#household-roster).

Set up, one step at a time, after the model egress is installed:

1. `sudo bash setup.sh` installs the firewall and creates the bridge. With the vault unlocked, `sudo control-plane/plutus-vault.sh unlock` creates `/plutus/gpt`.
2. In Plutus, create an API token (admin → Auth Tokens) and a tag `paperless-gpt-ocr-auto`. Put the token, helarctos's `LLAMA_SWAP_API_KEY` and `COMPOSE_PROFILES=ocr` in Plutus's `.env`, then `loft-ctl start plutus`.
3. Run the probes above.
4. Replace the OCR prompt: `printf 'Text Recognition:' | sudo tee /plutus/gpt/prompts/ocr_prompt.tmpl`, then restart `plutus-gpt`. The default prompt gives the model Paperless's Tesseract text and asks it to correct it, which anchors the second reading on the first and defeats the comparison; the plain task prompt gives it the page image alone.
5. Try it on a non-sensitive document: tag it by hand and confirm what changes in its content. No workflow tags new documents, so nothing is re-read unless you ask. Leave `OCR_SKIP_DIGITAL_PAGES` off: with it on, a pass on a born-digital PDF may skip pages it judges to have a clean text layer.

On a test document, check what happens to the Tesseract text before relying on a comparison; paperless-gpt's `db` holds a run log and undo history.

## Built-in AI

Paperless's own AI is enabled in [Compose](../../services/plutus/docker-compose.yml) and points at llama-swap (`PAPERLESS_AI_*`): suggestions on a document, chat, and similar documents. It is configured, not yet deployed, and not yet tried on 3.3.4.

- **Chat and suggestions:** `qwen3.6-35b-a3b`. It is not resident: the first request after a swap waits 23–36 s while it loads, and it evicts whichever large model is running, including a coding job's. The request timeout is 300 s. Which model stays resident is D18 ([models](../../automation/plans/models.md#sharing-the-gpu)).
- **Similar documents:** `embeddinggemma`, always loaded. Paperless indexes every document daily (`PAPERLESS_LLM_INDEX_TASK_CRON`, default 02:10), so the first run on a full archive is long; add the variable to Compose to move it.
- **Key:** helarctos's `LLAMA_SWAP_API_KEY` in Plutus's `.env`. Without it, AI requests fail with 401.
- **What leaves:** document text goes to helarctos over the LAN, as plain HTTP, for each request. It is held in memory there and not logged: after a real ID document went through, the container logs of llama-swap (helarctos) and of `plutus` and `plutus-gpt` held no document text or image data. Recheck after changing llama-swap's `logLevel`; its in-memory `/logs` buffer is not on disk and clears when the container is recreated.
- **Models:** fetch commands are under [Paperless models](sputnik.md#paperless-models).

## Bulk import

The consume folder is recursive, and each folder on a document's path becomes a tag (`consume/Tax/2019/w2.pdf` gets `Tax` and `2019`). Tags are flat: a folder name used in more than one branch becomes one shared tag. The filename becomes the title. After an import, move institution tags to correspondents with [plutus-tag-to-correspondent.sh](../../control-plane/plutus-tag-to-correspondent.sh) (`--dry-run` first; the correspondents must exist), then delete those tags and the ones that only carried the folder layout (years, `Documents`). Deleting a tag leaves its documents in place; wait until paperless-gpt has no documents queued, since it rewrites tag lists.

- Copy with `sudo rsync -rt --chown=1003:1003 <src>/ /plutus/consume/`. rsync writes each file under a temporary name and renames it into place, so Paperless never reads a half-copied file. Paperless deletes each file once it has been consumed, so it needs ownership.
- Only files with a supported extension are consumed; files without one are skipped, and Paperless does not unpack zips.
- Paperless rejects a duplicate (same checksum) as a failed task; failures are listed under Tasks.
- Documents from the consume folder have no owner, so both accounts can see them.
- The source tree is plaintext outside the vault, but with no [backup](#backups) it is also the second copy. Delete it once the import is checked and the documents exist elsewhere (paper or OneDrive).

## Backups

None running. Off-site backup (`document_exporter` output plus a Postgres dump into a restic repository on Google Drive) is [built but shelved](../operations/backups.md), so the vault is one copy on one disk: keep paper originals.

## Upgrades

Paperless and Postgres migrate one way. Run `document_exporter` and `pg_dump` first and read [upgrades](../operations/upgrades.md). The Postgres major (18) moves only with a dump and restore.

## Troubleshooting

- **`bind source path does not exist: /plutus/...`**: the vault is locked. Unlock it, then start Plutus.
- **`plutus-vault.sh` says another device is mounted**: something else is on `/plutus`; unmount it. The script never creates directories there.
- **502 from Caddy**: Plutus is stopped, or Mushr was not recreated after `plutus-proxy` was created (`sudo docker inspect mushr` should list both networks).
- **`plutus-db` logs `cannot create directory '/var/lib/postgresql'`**: `/plutus/db` is not traversable; it must be `755` (Postgres 18 only chowns its `18/docker` subdirectory).
- **Two-factor activation returns `{"success":false}`**: the code didn't match the secret. Paperless makes a new secret each time the dialog opens; delete the authenticator entry, open the dialog once, scan, and enter the code at once.
- **Database authentication fails at start**: `DB_PASSWORD` changed after the cluster was initialised. Fix it with `ALTER ROLE` inside `plutus-db`.
