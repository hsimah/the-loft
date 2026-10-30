# mercurius-wiki

n8n workflows `mercurius-wiki` and `mercurius-wiki-write`: wiki tools for Open WebUI's Household model, served by an MCP Server Trigger at `/mcp/mercurius-wiki` ([Household tools](../../../docs/services/sputnik.md#household-tools)). They call SilverBullet's HTTP API at `https://wiki.loft.hsimah.com/home/.fs` as account `sputnik` (`write` on `Home`); every request sends `X-Sync-Mode: true`, without which SilverBullet answers a `.md` path with the editor instead of the file.

| Tool | Does |
|---|---|
| `list_pages` | `GET /.fs`, names only |
| `read_page` | `GET /.fs/<path>`, markdown |
| `create_page` | Sub-workflow, mode `create`: writes a new page with `If-None-Match: *`; fails if it exists |
| `append_to_page` | Sub-workflow, mode `append`: adds text at the end of a `## heading` section (creating the section or page), written with `If-Match: <ETag>` so a concurrent edit makes it fail instead of being overwritten |

There is no delete or rewrite tool; revisions (attributed to `sputnik`) are the undo.

`mercurius-wiki-write` (Check → Read page → Edit → Write page → Result) rejects:

- paths that are not relative `.md` paths, contain `..`, or have a segment starting with `.`;
- text containing `space-lua`, `space-style`, `space-script`, `${`, `<!--#`, `<script` or `<iframe`, which SilverBullet runs as code in the browser of whoever opens the page.

## Import

1. Credential **Bearer Auth** `SilverBullet sputnik`: the `sputnik` account's API token from the SilverBullet Dashboard. `Open WebUI MCP` already exists.
2. Import `mercurius-wiki-write.json` (⋯ → Import from File); on **Read page** and **Write page** select `SilverBullet sputnik`; save and publish.
3. Import `mercurius-wiki.json`; select `Open WebUI MCP` on the trigger and `SilverBullet sputnik` on `list_pages` and `read_page`; on `create_page` and `append_to_page` pick workflow `mercurius-wiki-write` (inputs reload from it; `mode` must stay fixed and the others keep their `$fromAI` values). Save and publish.

Both workflows save neither successful nor manual executions.
