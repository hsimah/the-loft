# Briefing workflow

[briefing.json](briefing.json) is the source of truth for the nodes and prompt; [Modelfile.assistant](../Modelfile.assistant) holds the persona.

## Import

1. Import the JSON into n8n and rebind the Google OAuth2 and Ollama credentials (exported IDs don't carry over).
2. Google credential: read-only Gmail/Calendar scopes only ([setup](../../../docs/services/sputnik.md#google-oauth)). The workflow uses HTTP Request nodes, not Gmail action nodes.
3. Ollama credential base URL: `http://ollama:11434`; `sputnik-assistant` must exist.
4. Run manually, then **publish** to enable the schedule (saving a draft doesn't).
5. After editing in n8n, export back to JSON and check it for secrets before committing.

## Behavior

Schedule (6 h) → calendar (next 24 h) → Gmail list (last 6 h, no promotions/chats, max 25, no pagination) → fetch each (`format=full`, because snippets hid forwarded bill details) → digest (strips markup, 600 chars per body) → LLM → report → `/briefing/latest.json`.

- No last-success cursor: missed runs leave gaps.
- The prompt deliberately reports security notices and instruction-like mail instead of dropping them as noise.
- The sender/subject list is appended outside the model; it's the fetched batch, not proof of completeness or sender identity.
- The model has no tools; output is rendered with `textContent`.

**Empty inbox is untested**: the split/message nodes lack Always Output Data, so no mail may stop the run before the report. If so, add an explicit empty-mail branch to the report and re-export.

Check after changes: normal mail, no mail with events, nothing at all, a forwarded bill, a phishing/instruction email, >25 messages, and a failed step (stale output shows in `generatedAt`).

## Publication

n8n writes into `/opt/sputnik/briefing`; [Mushr](../../../docs/services/mushr.md) serves it with basic auth and Homepage reads its counts. LAN only.
