# Briefing workflow

[briefing.json](briefing.json) is the version-controlled workflow definition. The Code nodes and prompt live there; [Modelfile.assistant](../Modelfile.assistant) owns the shared persona. Do not maintain copied JavaScript or a second node-by-node build spec in this document.

## Import and configure

1. Import the JSON into n8n. Replace exported credential references with this installation's Google OAuth2 and Ollama credentials; exported IDs do not provision credentials.
2. Google OAuth must grant only Gmail/Calendar read-only scopes. The workflow uses HTTP Request nodes with the generic Google OAuth2 credential, not broad-purpose Gmail action nodes. See [Sputnik setup](../../../docs/services/sputnik.md#google-oauth).
3. Set the Ollama credential's base URL to `http://ollama:11434` and verify `sputnik-assistant` exists. This connection entry is not Ollama authentication.
4. Run manually and validate the cases below. Publish the workflow to enable its schedule; saving a draft alone is insufficient. Verify actual scheduled executions after import.
5. After changes in n8n, export the tested workflow back to JSON. Inspect exports for credentials/secrets before committing.

## Data flow and limits

Schedule → calendar → Gmail list → split IDs → message fetch → digest → LLM chain → report assembly → file conversion → `/briefing/latest.json`.

The trigger interval is 6 hours. Mail queries look back 6 hours, exclude promotions/chats, and request at most 25 messages without pagination. Calendar queries look forward 24 hours. These windows intentionally differ. There is no persisted last-success cursor, so missed runs can leave gaps and retries can overlap.

Message fetch uses `format=full`: metadata snippets hid useful bill details in a recorded forwarded-message incident. The digest walks MIME parts, strips markup/forwarding boilerplate and truncates each body to 600 characters. Amounts or deadlines beyond that limit may still be omitted. Inspect the digest when evaluating a bad summary.

The prompt explicitly includes account/security notices and attempted instructions, even when automated. Prior tests showed both categories being silently skipped as noise. Preserve that distinction without asking the model to certify a message's authenticity.

Report assembly appends sender/subject and calendar entries without passing that list through the model. It helps compare output with fetched inputs, but is filtered/capped by the query and does not prove sender identity or mailbox completeness. The renderer displays text without turning injected markup into active content.

## Required validation

| Case | Expected observation |
|---|---|
| Ordinary mail and events | Counts and report match the fetched batch; amounts/times have supporting input |
| No new mail, calendar populated | A fresh file still includes upcoming events |
| No mail or events | A fresh file explicitly reports no items |
| Forwarded bill | The digest contains the relevant body, not only forwarded headers |
| Security alert / instruction-like email | Reported for the user to inspect; no API write or external action |
| More than 25 matching messages | Recognize incomplete coverage; do not interpret the manifest as the whole window |
| Failed fetch/inference/write | Execution failure is visible and stale output is distinguishable by generatedAt |

**Unresolved empty-inbox path:** the tracked export has no Always Output Data setting on its split/message nodes. A downstream Code-node try/catch cannot run if an upstream branch produces no items. Validate this on the deployed n8n version before relying on the schedule; if it stops, add an explicit empty-mail branch that reaches digest/report generation, test both branches, then export it. Merely setting Always Output Data on an unexecuted downstream node is insufficient.

The workflow has not been executed by the repository cleanup. This runtime check is tracked in [maintenance](../../../plans/maintenance.md). Do not claim import or schedule validation from JSON syntax alone.

## Publication

The JSON lands in the host's `/opt/sputnik/briefing` via n8n's `/briefing` mount and file-access allowlist. [Mushr](../../../docs/services/mushr.md) serves it alongside the tracked renderer under basic auth; Homepage reads counts/freshness. Keep the route off the public tunnel.

The write is not atomic. Check the n8n execution and `generatedAt` when the page is stale or unreadable. The read-only Google credential cannot email the result; adding delivery would be a separate capability change.
