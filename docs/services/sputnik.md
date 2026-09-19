# Sputnik — local assistant

[Compose](../../services/sputnik/docker-compose.yml) runs Ollama (`engine`), Open WebUI (`chat`) and n8n (`agent`) on space-needle with `COMPOSE_PROFILES=engine,chat,agent`. Other fleet hosts do not run inference. The [briefing workflow](../../services/sputnik/workflows/briefing.md) reads Gmail/Calendar, summarizes them and publishes a local page.

## State and boundaries

| Host path | Contents |
|---|---|
| `/mammoth/sputnik/models` | Ollama weights |
| `/opt/sputnik/open-webui` | Users, chat history and UI state |
| `/opt/sputnik/n8n` | Container home; `.n8n/` holds DB and encrypted credentials |
| `/opt/sputnik/briefing` | Published `latest.json` |

Back up the application data **and** `N8N_ENCRYPTION_KEY`. Losing the key makes stored credentials unusable; it does not encrypt the whole directory. Treat chat history, execution records and published mail summaries as private data.

Ollama has no authentication. Its host port is loopback-only; containers on `loft-proxy` can reach `ollama:11434`. It has no Caddy route. Open WebUI/n8n have application logins; the static briefing route uses Caddy basic auth. Keep all three names off the remotely managed Cloudflare Tunnel. Live tunnel configuration and installed tools must be checked separately from this repo.

The exported briefing uses fixed HTTP requests followed by a tool-less LLM chain. Model output is written as data and rendered with `textContent`; no model-generated API action is wired downstream. This constrains that workflow, not every possible Open WebUI conversation or future n8n edit. Output may still omit facts, invent details or repeat phishing instructions. The appended sender/subject list is built outside the model but covers only the fetched, filtered batch; it is not a complete mailbox or authenticity check.

## First setup

1. Copy [.env.example](../../services/sputnik/.env.example). Generate separate WebUI and n8n keys with `openssl rand -hex 32`, set LOFT_DOMAIN/timezone and profiles, then provision the declared host directories.
2. Start Sputnik. Use `bash services/sputnik/bench.sh` to inspect available memory; without installed models it exits after sizing guidance. Pull the base model chosen in [Modelfile.assistant](../../services/sputnik/Modelfile.assistant), then build the persona:

   ```bash
   sudo docker exec -it ollama ollama pull qwen3:30b-a3b
   sudo docker exec -i ollama ollama create sputnik-assistant \
     -f /dev/stdin < services/sputnik/Modelfile.assistant
   ```

3. Create Open WebUI's first account at `https://sputnik.loft.hsimah.com`, select `sputnik-assistant`, disable signup in the service environment and recreate the group. Create n8n's owner account at `https://n8n.loft.hsimah.com`.
4. Configure Google OAuth as below, then [import, bind credentials and validate the workflow](../../services/sputnik/workflows/briefing.md).
5. Configure the [Mushr briefing credential](mushr.md#briefing-mount-and-password) and matching [Homepage](houstn.md) credential. After a successful run, open `https://briefing.loft.hsimah.com` and Homepage's Briefing tab.

Rebuild the derived model after editing its Modelfile. The persona is guidance, not an access-control mechanism; tool wiring and credential scopes establish capabilities.

## Google OAuth

Enable Gmail and Calendar APIs in a Google Cloud project, create a web OAuth client, and register the exact callback `https://n8n.loft.hsimah.com/rest/oauth2-credential/callback`. In n8n use the generic Google OAuth2 credential with:

```text
https://www.googleapis.com/auth/gmail.readonly
https://www.googleapis.com/auth/calendar.readonly
```

Bind it to the workflow's HTTP Request nodes. Complete authorization from a LAN browser; the browser follows the callback to n8n. Check the consent screen's publishing status and token lifetime if access expires; testing-mode credentials may need reauthorization. Follow Google's current consent/verification requirements for the intended users rather than assuming a production setting waives them.

Do not widen scopes to fix an unrelated workflow error. `gmail.compose` allows **sending** as well as managing drafts; it is not a human-send-only boundary. [Google scope reference](https://developers.google.com/workspace/gmail/api/auth/scopes).

## Performance record

Observed 2026-08-01 on an i9-12900H, 31 GB RAM, CPU inference, `qwen3:30b-a3b`, approximately 2,070 prompt tokens:

| Threads | Prefill tok/s | Generation tok/s |
|---|---|---|
| 20 | 45.3 | 10.9 |
| 6 | 46.6 | 11.8 |
| 12 | 45.1 | 14.5 |

The selected Modelfile uses 12 threads and 16,384 context tokens. Reported resident memory was about 20 GB and first-token wait about 45 seconds. These are dated measurements, not capacity guarantees. Thread count does not pin execution to P-cores; Compose has no CPU-affinity setting.

`OLLAMA_KEEP_ALIVE=-1` keeps the model loaded, trading resident RAM for fewer cold loads. Re-measure with `bash services/sputnik/bench.sh sputnik-assistant` after model/hardware changes. It estimates first-token time from load plus prompt-evaluation duration; it does not measure streamed first-token delivery.

## Troubleshooting

- **Missing models:** `sudo docker exec ollama ollama list`; check consumers use `http://ollama:11434`, not their own localhost.
- **Slow requests:** inspect model residency, load duration, prompt size, memory pressure and measured throughput. Repeated loading is one possible cause, not the only one.
- **Fabricated/omitted detail:** compare the fetched message, sanitized digest and final report. The workflow limits mail count and body length; context truncation is only one possible cause. Do not automatically raise the context size.
- **n8n home errors:** UID 1003 needs a writable home. Preserve the whole `/home/node` mount and explicit HOME/N8N_USER_FOLDER values; mounting only `.n8n` leaves sibling cache paths unwritable.
- **Briefing write denied:** preserve `/briefing` in `N8N_RESTRICT_FILE_ACCESS_TO`, verify the bind mount and ownership. Keep credential-file protections enabled.
- **Briefing stale:** check workflow publication and executions, particularly the empty-inbox case described in the workflow guide. `active: true` in an export does not prove an imported workflow is published/running.
- **Profile dependency errors:** engine consumers use long-form `depends_on` with `condition: service_started` and `required: false` so profiles can be validated separately. Preserve this configuration when editing profiles.

The page's JSON write is not atomic. Readers may see a parse error during publication; check execution logs and retry. The renderer and Caddy data mounts remain separate, read-only mounts as documented in Mushr.
