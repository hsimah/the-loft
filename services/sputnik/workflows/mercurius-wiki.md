# mercurius-wiki

n8n workflows `mercurius-wiki` and `mercurius-wiki-write`: wiki tools for Open WebUI's Household model, served by an MCP Server Trigger at `/mcp/mercurius-wiki` ([Household tools](../../../docs/services/sputnik.md#household-tools)). They call SilverBullet's HTTP API at `https://wiki.loft.hsimah.com/home/.fs` as account `sputnik` (`write` on `Home`); every request sends `X-Sync-Mode: true`, without which SilverBullet answers a `.md` path with the editor instead of the file.

| Tool | Does |
|---|---|
| `list_pages` | `GET /.fs`, names only |
| `read_page` | `GET /.fs/<path>`, markdown |
| `read_conventions` | `GET /.fs/meta/conventions.md`: the household's filing and style rules, read before every write; may point to per-area conventions pages |
| `create_page` | Sub-workflow, mode `create`: writes a new page with `If-None-Match: *`; fails if it exists |
| `append_to_page` | Sub-workflow, mode `append`: adds text at the end of a `## heading` section (creating the section or page), written with `If-Match: <ETag>` so a concurrent edit makes it fail instead of being overwritten |

There is no delete or rewrite tool; revisions (attributed to `sputnik`) are the undo.

`mercurius-wiki-write` (Check → Read page → Edit → Write page → Result) rejects:

- paths that are not relative `.md` paths, contain `..`, have a segment starting with `.`, or are under `Library/` or `Repositories/` (SilverBullet's own files, mostly Space Lua);
- text containing `space-lua`, `space-style`, `space-script`, `${`, `<!--#`, `<script` or `<iframe`, which SilverBullet runs as code in the browser of whoever opens the page;
- any input containing `$fromAI`, i.e. a field left as fixed text instead of an expression (see Import).

## Import

1. Credential **Bearer Auth** `SilverBullet sputnik`: the `sputnik` account's API token from the SilverBullet Dashboard. `Open WebUI MCP` already exists.
2. Import `mercurius-wiki-write.json` (⋯ → Import from File); on **Read page** and **Write page** select `SilverBullet sputnik`; save and publish.
3. Import `mercurius-wiki.json`; select `Open WebUI MCP` on the trigger and `SilverBullet sputnik` on `list_pages`, `read_page` and `read_conventions`; on `create_page` and `append_to_page` pick workflow `mercurius-wiki-write`. Picking it reloads **Workflow Inputs** and drops the mapped values, leaving the model a single `input` parameter (writes then fail with an empty path), so set them again: `mode` fixed (`create` or `append`); `path`, `text` and, on `append_to_page`, `heading` as `$fromAI(...)` expressions, copied from this JSON or made with each field's ✨ button. Each must show the **fx** badge: as fixed text, `$fromAI` drops out of the tool schema and its literal text is sent. Save and **publish**; the MCP trigger serves the published version, not the saved draft. Start a new chat.

The model reads [meta/conventions.md](https://wiki.loft.hsimah.com/home/meta/conventions) before writing; filing, naming and style rules belong there, not in the system prompt. Without that page, writes stop.

Both workflows save neither successful nor manual executions.
