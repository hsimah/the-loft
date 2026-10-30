# Mercurius: household wiki and documents

One Compose group on the encrypted volume holds the wiki and the document archive: [Paperless-ngx](https://docs.paperless-ngx.com) stores every document, and [SilverBullet](https://docs.silverbullet.md) is the index where notes about them live. Open WebUI and n8n read and write both. Live since 2026-10-29; the setup is on the [service page](../services/mercurius.md). This page holds the work still to come. Document work (OCR, re-checks, intake) is on [documents](documents.md); see the [roadmap](roadmap.md).

## Preview widget

A Space Lua widget that renders a Paperless link as a card (title, correspondent, date, thumbnail). It calls Paperless's API from the server through `net.proxyFetch` to `http://paperless:8000` on the internal network, so no CORS. The token sits in the space, readable by every member; both of you are superusers, so that is acceptable.

## Chat and n8n access

Open WebUI and n8n stay in [Sputnik](../services/sputnik.md) and reach `wiki.` and `paperless.` through Caddy with API tokens. Accepted: answers, chats and n8n execution data that quote documents are stored unencrypted under `/opt/sputnik` on space-needle.

- **Tools as n8n workflows**, exposed through n8n's MCP Server Trigger; Open WebUI connects as an MCP client. One tool set serves both apps, no Python, and the workflows are exported to `services/sputnik/workflows/` ([workflows](workflows.md)). n8n 2.44.7's MCP Server Trigger serves Streamable HTTP with bearer auth; Open WebUI 0.12.4's MCP client speaks Streamable HTTP only. Current setup: [Household tools](../services/sputnik.md#household-tools).
- **Wiki tools**: list, read, create and append, as SilverBullet account `sputnik` through its HTTP API ([mercurius-wiki](../../services/sputnik/workflows/mercurius-wiki.md)). Writes go straight to the page and the tool returns what it added; there is no delete or rewrite, and revisions are the undo. Writes that contain Space Lua or inline expressions are refused. Built 2026-10-30, not yet imported. SilverBullet has no server-side search, so the model works from the page list.
- **Document tools**: search and read, live 2026-10-30. Read-only by permission: they use Paperless user `sputnik`, which has View only (writes return 403) and sees documents with no owner or shared with it; documents you upload through the UI are owned by you, so share them for chat to see them. `read_document` does not truncate (n8n truncates only text and HTML responses); if a long document overflows the 32k context, raise `--ctx-size` or truncate in a Code Tool.
- **Model**: `qwen3.6-35b-a3b`, resident (D18). It has one slot, shared with Paperless, so a chat waits behind a Paperless request in flight.

### Keeping web and household data apart

No chat or workflow gets both wiki/document tools and a web tool (search, URL fetch, sending mail). This is enforced by settings, not by the network. In Open WebUI 0.12.4 (read in `utils/tools.py`):

- `search_web` and `fetch_url` are injected together, only when web search is on globally (`ENABLE_WEB_SEARCH`, default off, and off today), the model has the Web Search capability, the chat's Web Search toggle is on, and the user has `web_search` permission. Today no model can fetch a URL.
- `execute_code` is on by default (`ENABLE_CODE_INTERPRETER`) and runs Pyodide (`CODE_INTERPRETER_ENGINE`) in the browser, which can make network requests. It needs the chat's Code Interpreter toggle. Turn it off in Admin → Settings → Code Execution: the database wins over the Compose variable after the first start. Code Execution on the same page (`ENABLE_CODE_EXECUTION`) adds a Run button to Python code blocks, also Pyodide in the browser; nothing runs without a click, but it goes off too.
- A **Household** model in Workspace → Models: base `qwen3.6-35b-a3b`, the wiki/document tool server attached, the **Builtin Tools** capability off (no web, code, image, memory or notes tools, even if those are enabled globally later; each built-in category otherwise defaults to on), Memory and Vision off, function calling left at the default (native; not Legacy). The other built-in categories (memory, notes, chats) stay inside Open WebUI's own data.
- Tool servers can still be toggled per chat from Integrations, and both of you are admins, so the rule holds by habit. When web search arrives (D23), web tools get their own n8n workflow and MCP endpoint, attached only to a separate model.

Markdown images in model replies are fetched by the browser; a reply quoting a document could carry data out that way. Low risk for documents you file yourself; revisit before any untrusted feed (mail, web pages) reaches these tools.

## Later

- Email to the wiki and web clippings are deprioritised: chat with wiki write tools covers them for now ([intake](intake.md)).
- A public, LAN-only space for guests (bin schedule, dog medication): a separate SilverBullet instance off the vault, so guests never share a server with the private wiki and it stays up while the vault is locked. Needs a name and a check of 2.12's read-only options.
- Overnight wiki upkeep (summaries, links between pages) as an n8n workflow using the same tools, local models only. The Forgejo PR agent on the [#152](https://github.com/hsimah/the-loft/issues/152) harness is dropped: the wiki has no repo outside the vault.
- Off-LAN access through Tailscale (D9).
- Obsidian is dropped with the Forgejo sync.
