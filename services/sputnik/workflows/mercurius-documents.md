# mercurius-documents

n8n workflow `Paperless`: read-only document tools for Open WebUI's Household model, served by an MCP Server Trigger at `/mcp/mercurius-documents` ([Household tools](../../../docs/services/sputnik.md#household-tools)).

| Tool | Call |
|---|---|
| `search_documents` | `GET /api/documents/?query=<q>&page_size=10&fields=id,title,created`: Paperless full-text search; results carry `__search_hit__` highlights |
| `read_document` | `GET /api/documents/<id>/?fields=id,title,created,content`; not truncated |

Credentials, created in n8n before importing (the export names them but holds no secrets):

- `Open WebUI MCP`: Bearer Auth, a random secret (`openssl rand -hex 32`); the same value is the bearer key on Open WebUI's tool server connection.
- `Paperless sputnik (read-only)`: Header Auth, `Authorization: Token <token>` for Paperless user `sputnik`, which has View permissions only.

Import with ⋯ → Import from File, reselect both credentials on the nodes, then publish. Successful and manual executions are not saved, since they hold document text; failed ones are kept for debugging.
