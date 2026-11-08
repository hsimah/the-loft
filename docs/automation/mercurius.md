# Mercurius: household wiki and documents

One Compose group on the encrypted volume holds the wiki and the document archive: [Paperless-ngx](https://docs.paperless-ngx.com) stores every document, and [SilverBullet](https://docs.silverbullet.md) is the index where notes about them live. Open WebUI and n8n read and write both. Live since 2026-10-29; the setup is on the [service page](../services/mercurius.md). This page holds the work still to come. Document work (OCR, re-checks, intake) is on [documents](documents.md); see the [roadmap](roadmap.md).

## Preview widget

A Space Lua widget that renders a Paperless link as a card (title, correspondent, date, thumbnail). It calls Paperless's API from the server through `net.proxyFetch` to `http://paperless:8000` on the internal network, so no CORS. The token sits in the space, readable by every member; both of you are superusers, so that is acceptable.

## Chat and n8n access

Open WebUI and n8n stay in [Sputnik](../services/sputnik.md) and reach `wiki.` and `paperless.` through Caddy with API tokens. Accepted: answers, chats and n8n execution data that quote documents are stored unencrypted under `/opt/sputnik` on space-needle.

- **Tools as n8n workflows**, exposed through n8n's MCP Server Trigger; Open WebUI connects as an MCP client. One tool set serves both apps and the workflows are exported to `services/sputnik/workflows/` ([workflows](workflows.md)). n8n 2.45.7's MCP Server Trigger serves Streamable HTTP with bearer auth; Open WebUI 0.12.5's MCP client speaks Streamable HTTP only. Current setup: [Household tools](../services/sputnik.md#household-tools).
- **Wiki tools**: list, read, read conventions, create and append, as SilverBullet account `sputnik` through its HTTP API ([mercurius-wiki](../../services/sputnik/workflows/mercurius-wiki.md)), live 2026-11-01. The model reads `meta/conventions.md` before every write; filing and style rules live there, not in the prompt. Writes go straight to the page and the tool returns what it added; there is no delete, and revisions are the undo. Writes that contain Space Lua or inline expressions are refused. SilverBullet has no server-side search, so the model works from the page list.
- **Wiki rewrites**: the native Open WebUI tool `wiki_edit` with the `wiki-editing` skill ([Household tools](../services/sputnik.md#household-tools)). It is not an n8n workflow because only native tools can render the diff in chat. The model proposes a full page, you approve the diff, and the write is guarded by the page's ETag. Live 2026-11-07.
- **Document tools**: search and read, live 2026-10-30. Read-only by permission: they use Paperless user `sputnik`, which has View only (writes return 403) and sees documents with no owner or shared with it; documents you upload through the UI are owned by you, so share them for chat to see them. `read_document` does not truncate (n8n truncates only text and HTML responses); if a long document overflows the 32k context, raise `--ctx-size` or truncate in a Code Tool.
- **Model**: `qwen3.6-35b-a3b`, resident (D18). It has one slot, shared with Paperless, so a chat waits behind a Paperless request in flight.

### Keeping web and household data apart

No chat or workflow gets both wiki/document tools and a web tool (search, URL fetch, sending mail). This is enforced by settings, not by the network. In Open WebUI 0.12.5 (read in `utils/tools.py`):

- `search_web` and `fetch_url` are injected together, only when web search is on globally (`ENABLE_WEB_SEARCH`, default off, and off today), the model has the Web Search capability, the chat's Web Search toggle is on, and the user has `web_search` permission. Today no model can fetch a URL.
- `execute_code` is on by default (`ENABLE_CODE_INTERPRETER`) and runs Pyodide (`CODE_INTERPRETER_ENGINE`) in the browser, which can make network requests. It needs the chat's Code Interpreter toggle. Turn it off in Admin → Settings → Code Execution: the database wins over the Compose variable after the first start. Code Execution on the same page (`ENABLE_CODE_EXECUTION`) adds a Run button to Python code blocks, also Pyodide in the browser; nothing runs without a click, but it goes off too.
- A **Household** model in Workspace → Models: base `qwen3.6-35b-a3b`, the wiki/document tool server attached, the **Builtin Tools** capability off (no web, code, image, memory or notes tools, even if those are enabled globally later; each built-in category otherwise defaults to on), Memory and Vision off, function calling left at the default (native; not Legacy). The other built-in categories (memory, notes, chats) stay inside Open WebUI's own data.
- Tool servers can still be toggled per chat from Integrations, and both of you are admins, so the rule holds by habit. When web search arrives (D23), web tools get their own n8n workflow and MCP endpoint, attached only to a separate model.

Markdown images in model replies are fetched by the browser; a reply quoting a document could carry data out that way. Low risk for documents you file yourself; revisit before any untrusted feed (mail, web pages) reaches these tools.

## Wiki editing and review

Planned. Page rewrites with approval are covered by `wiki_edit` (above). Larger restructuring (splitting a page into linked sub-pages, merging, fixing links) needs a backlink tool and a model with more context than the 32k Household model.

1. **Tools.** `find_links(page)` fetches every page in n8n and returns those linking to `[[Page]]` or `[[Page#Section]]`. SilverBullet has no backlink API, and its rename only rewrites links in the browser. No delete: a move is a new page plus a stub, deleted by hand.
2. **Wiki editor model.** A second Open WebUI model on `gpt-oss-120b` (131k context, loads on demand beside the household set) with the wiki tools, `wiki_edit` and `find_links`. Extend the `wiki-editing` skill with the refactor procedure: read the page and its backlinks, propose a plan and wait for approval, create sub-pages, rewrite the parent, then fix `#Section` links. That order leaves duplicates, not losses, if it stops part-way.
3. **Monthly review**, an n8n schedule at about 02:00 on the 1st, under the [GPU sharing rules](models.md#sharing-the-gpu). Code nodes fetch every page and compute sizes, the link graph, orphans, broken links and paths that break the conventions. `qwen3.5-122b` then takes one area at a time with the conventions and those facts and returns JSON suggestions: splits, merges, missing links, misplaced or stale content, gaps in the conventions. The job writes only a report page, `meta/reviews/<YYYY-MM>.md`, through `create_page`, and unloads the large model at the end (`ttl: 0` keeps it otherwise; check llama-swap's unload endpoint). You act on suggestions in the Wiki editor or by hand.
4. Later, perhaps: approve suggestions on the report page and have them applied.

## Later

- Email to the wiki and web clippings are deprioritised: chat with wiki write tools covers them for now ([intake](intake.md)).
- A public, LAN-only space for guests (bin schedule, dog medication): a separate SilverBullet instance off the vault, so guests never share a server with the private wiki and it stays up while the vault is locked. Needs a name and a check of 2.12's read-only options.
- Off-LAN access through Tailscale (D9).
- Obsidian is dropped with the Forgejo sync.
