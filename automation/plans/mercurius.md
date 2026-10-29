# Mercurius: household wiki and documents

One Compose group on the encrypted volume holds the wiki and the document archive: [Paperless-ngx](https://docs.paperless-ngx.com) stores every document, and [SilverBullet](https://docs.silverbullet.md) is the index where notes about them live. Open WebUI and n8n read and write both. **Live since 2026-10-29** ([service page](../../docs/services/mercurius.md)); only step 14 of the [migration](#migration) is left. Document work (OCR, re-checks, intake) is on [documents](documents.md); see the [roadmap](roadmap.md).

## Target

| Piece | Proposed |
|---|---|
| Group | `services/mercurius` (in the repo), replacing Plutus and the wiki-only Mercurius |
| Containers | `paperless`, `paperless-gpt`, `silverbullet`, `mercurius-db`, `mercurius-redis`, `mercurius-tika`, `mercurius-gotenberg`; later `mercurius-fetch` ([names](names.md)) |
| Storage | The LUKS2 volume, renamed `mercurius` and mounted at `/mercurius`: Paperless's directories as today, plus `silverbullet/` (SilverBullet's data folder). Unlocked by hand after each boot; nothing in the group starts while it is locked |
| Hostnames | `wiki.loft.hsimah.com` (SilverBullet), `paperless.loft.hsimah.com`. LAN only until Tailscale (D9); never on the tunnel |
| Networks | `mercurius-proxy` (internal, shared with Caddy) and the group's internal network. Only Paperless and paperless-gpt keep the route to llama-swap (`mercurius-llm` bridge and nft table, as built for Plutus). SilverBullet has no route out, so `net.proxyFetch` reaches only the group's internal network |
| Wiki history | SilverBullet's revisions in **Managed** mode: a git repository in the space folder, on the vault. No remote: removing the connection keeps files and history ([docs](https://docs.silverbullet.md/Revisions)). Browse and restore with `Revisions: *` |
| Backup | One vault restic job: Paperless export, Postgres dump and the SilverBullet folder, `.git` included. Shelved with the rest ([backups](backups.md)); until then the vault is one copy |

The wiki may hold anything: amounts, document details, OCR text. The "links only" rule ends with the move.

## Migration

The repo holds the merged group ([service page](../../docs/services/mercurius.md)); the host still runs Plutus and the old wiki. Start once the OneDrive bulk import has finished: `/plutus/consume` is empty, Paperless lists no queued or running tasks, and no document carries `paperless-gpt-ocr-auto`.

Run from `/srv/the-loft` on space-needle, one at a time. Steps 1–3 use the **old** checkout: after the pull, `loft-ctl` no longer knows `plutus` and `plutus-vault.sh` is gone.

1. In SilverBullet's dashboard (`https://mercurius.loft.hsimah.com/.dashboard`), disconnect the `home` space's git repository. Disconnecting leaves the remote in `.git/config`; remove it with `sudo -u littledog git -C /mammoth/mercurius/spaces/home remote remove origin`, then check the history stayed: `sudo -u littledog git -C /mammoth/mercurius/spaces/home log --oneline -3`.
2. `loft-ctl stop mercurius plutus`
3. `sudo control-plane/plutus-vault.sh lock`
4. `git pull`, then `mv -f services/plutus/.env services/mercurius/.env` and `rmdir services/plutus`. Plutus's `.env` has every variable the group needs; the wiki's held only `TZ`.
5. `sudo lvrename ubuntu-vg plutus mercurius`
6. `sudo control-plane/mercurius-vault.sh unlock`: opens the volume as `mercurius`, mounts it at `/mercurius` and creates `silverbullet/`. The XFS label stays `plutus`; nothing mounts by label.
7. `sudo rsync -aHAX /mammoth/mercurius/ /mercurius/silverbullet/`, then `sudo ls -la /mercurius/silverbullet` (owner littledog).
8. Rewrite links to the old Paperless name: `sudo grep -rl --exclude-dir=.git 'plutus\.loft\.hsimah\.com' /mercurius/silverbullet/spaces`, then for those files `sudo -u littledog sed -i 's/plutus\.loft\.hsimah\.com/paperless.loft.hsimah.com/g' <files>` (as littledog, so the pages keep their owner). SilverBullet commits the change once it starts.
9. Remove the old firewall: `sudo systemctl disable --now loft-plutus-egress`, `sudo rm /etc/systemd/system/loft-plutus-egress.service /etc/loft/plutus-egress.nft`, `sudo systemctl daemon-reload`, `sudo nft delete table inet loft_plutus`, `sudo rmdir /plutus`.
10. `sudo bash setup.sh`: creates `mercurius-proxy` and `mercurius-llm`, installs the new firewall, recreates Mushr on the new network and starts the group.
11. `sudo docker network rm plutus-proxy plutus-llm`, then `loft-ctl health mercurius` (the wiki check fails until step 12).
12. Every request redirects to `primaryUrl` in `/mercurius/silverbullet/server.json`, still the old name: `sudo docker stop silverbullet`, change it to `https://wiki.loft.hsimah.com` with `sudo nano` (keeps the owner), start it. Then at `https://wiki.loft.hsimah.com/.dashboard`, check `home` is bound to `wiki.loft.hsimah.com` and set revisions to **Managed** if disconnecting changed it. Check `Revisions:` shows the old history.
13. Run the [egress probes](../../docs/services/mercurius.md#model-egress). Sign in again to Paperless at the new name and point any phone app at it. Update Uptime Kuma monitors or bookmarks that use `mercurius.` or `plutus.` (not in the repo).
14. After a few days' use: `sudo rm -rf /mammoth/mercurius`, and archive or delete the Forgejo repo `hsimah/mercurius` (your call; it holds only pre-move content). Then make this page's Target current-state and delete this section.

## Preview widget

A Space Lua widget that renders a Paperless link as a card (title, correspondent, date, thumbnail). It calls Paperless's API from the server through `net.proxyFetch` to `http://paperless:8000` on the internal network, so no CORS. The token sits in the space, readable by every member; both of you are superusers, so that is acceptable.

## Chat and n8n access

Open WebUI and n8n stay in [Sputnik](../../docs/services/sputnik.md) and reach `wiki.` and `paperless.` through Caddy with API tokens. Accepted: answers, chats and n8n execution data that quote documents are stored unencrypted under `/opt/sputnik` on space-needle.

- **Tools as n8n workflows**, exposed through n8n's MCP Server Trigger; Open WebUI connects as an MCP client. One tool set serves both apps, no Python, and the workflows are exported to `services/sputnik/workflows/` ([workflows](workflows.md)). Verify MCP on the pinned n8n 2.44.7 and Open WebUI 0.12.4 before building.
- **Wiki tools**: search, list, read, write a page. Writes go straight to the page and the tool returns what it changed; revisions are the undo.
- **Document tools**: search and read, read-only to start.
- **Model**: `qwen3.6-35b-a3b`, the one served model suited to tool calls. It is not resident, so a chat's first call waits 23–36 s and evicts the coder (D18).

### Keeping web and household data apart

No chat or workflow gets both wiki/document tools and a web tool (search, URL fetch, sending mail). This is enforced by settings, not by the network. In Open WebUI 0.12.4 (read in `utils/tools.py`):

- `search_web` and `fetch_url` are injected together, only when web search is on globally (`ENABLE_WEB_SEARCH`, default off, and off today), the model has the Web Search capability, the chat's Web Search toggle is on, and the user has `web_search` permission. Today no model can fetch a URL.
- `execute_code` is on by default (`ENABLE_CODE_INTERPRETER`) and runs Pyodide (`CODE_INTERPRETER_ENGINE`) in the browser, which can make network requests. It needs the chat's Code Interpreter toggle. Turn it off in Admin → Settings → Code Execution: the database wins over the Compose variable after the first start.
- A **Household** model in Workspace → Models: the wiki/document tool server attached; Web Search, Code Interpreter and Image Generation capabilities off. The other built-in categories (memory, notes, chats) stay inside Open WebUI's own data.
- Tool servers can still be toggled per chat from Integrations, and both of you are admins, so the rule holds by habit. When web search arrives (D23), web tools get their own n8n workflow and MCP endpoint, attached only to a separate model.

Markdown images in model replies are fetched by the browser; a reply quoting a document could carry data out that way. Low risk for documents you file yourself; revisit before any untrusted feed (mail, web pages) reaches these tools.

## Later

- Email to the wiki and web clippings are deprioritised: chat with wiki write tools covers them for now ([intake](intake.md)).
- A public, LAN-only space for guests (bin schedule, dog medication): a separate SilverBullet instance off the vault, so guests never share a server with the private wiki and it stays up while the vault is locked. Needs a name and a check of 2.12's read-only options.
- Overnight wiki upkeep (summaries, links between pages) as an n8n workflow using the same tools, local models only. The Forgejo PR agent on the [#152](https://github.com/hsimah/the-loft/issues/152) harness is dropped: the wiki has no repo outside the vault.
- Off-LAN access through Tailscale (D9).
- Obsidian is dropped with the Forgejo sync.

## Open questions

- D19: do these planning pages move into the wiki? Recommendation: no, they describe fleet config and belong next to it.
