# Mercurius: household wiki and documents

One Compose group on the encrypted volume holds the wiki and the document archive: [Paperless-ngx](https://docs.paperless-ngx.com) stores every document, and [SilverBullet](https://docs.silverbullet.md) is the index where notes about them live. Open WebUI and n8n read and write both. **Proposed**: today the wiki runs as Mercurius on `/mammoth` with git sync to Forgejo ([service page](../../docs/services/mercurius.md)), and Paperless runs as Plutus on the vault ([service page](../../docs/services/plutus.md)). Document work (OCR, re-checks, intake) is on [documents](documents.md); see the [roadmap](roadmap.md).

## Target

| Piece | Proposed |
|---|---|
| Group | `services/mercurius`, replacing `services/plutus` and the current `services/mercurius` |
| Containers | `paperless`, `paperless-gpt`, `silverbullet`, `mercurius-db`, `mercurius-redis`, `mercurius-tika`, `mercurius-gotenberg`; later `mercurius-fetch` ([names](names.md)) |
| Storage | The LUKS2 volume, renamed `mercurius` and mounted at `/mercurius`: Paperless's directories as today, plus `silverbullet/` (SilverBullet's data folder). Unlocked by hand after each boot; nothing in the group starts while it is locked |
| Hostnames | `wiki.loft.hsimah.com` (SilverBullet), `paperless.loft.hsimah.com`. LAN only until Tailscale (D9); never on the tunnel |
| Networks | `mercurius-proxy` (internal, shared with Caddy) and the group's internal network. Only Paperless and paperless-gpt keep the route to llama-swap (`mercurius-llm` bridge and nft table, as built for Plutus). SilverBullet has no route out, so `net.proxyFetch` reaches only the group's internal network |
| Wiki history | SilverBullet's revisions in **Managed** mode: a git repository in the space folder, on the vault. No remote: removing the connection keeps files and history ([docs](https://docs.silverbullet.md/Revisions)). Browse and restore with `Revisions: *` |
| Backup | One vault restic job: Paperless export, Postgres dump and the SilverBullet folder, `.git` included. Shelved with the rest ([backups](backups.md)); until then the vault is one copy |

The wiki may hold anything: amounts, document details, OCR text. The "links only" rule ends with the move.

## Migration

Start once the OneDrive bulk import has finished: the consume folder is empty and no Paperless tasks are queued. The runbook is written with the build; the order is:

1. Renames in the repo: Compose group, `plutus-vault.sh` → `mercurius-vault.sh`, `plutus-proxy`, `plutus-llm`, the nft table, host.conf (`SERVICES`, `SERVICE_REQUIRES_MOUNT`, health URLs, `BACKUP_JOBS`), Caddy routes, `PAPERLESS_URL`. Paperless's data is unchanged.
2. In SilverBullet's dashboard, disconnect the space's git repository.
3. Stop both groups. Rename the LV, mount at `/mercurius`, copy `/mammoth/mercurius` to `/mercurius/silverbullet` (owner littledog).
4. Start the new group. Rebind the `household` space to `wiki.loft.hsimah.com`, check revisions are present, and rewrite any `plutus.loft…` links in pages.
5. After checking: remove `/mammoth/mercurius`, and archive or delete the Forgejo repo `hsimah/mercurius` (your call; it holds only pre-move content).

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
