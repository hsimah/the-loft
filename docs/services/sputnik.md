# Sputnik — local assistant

[Compose](../../services/sputnik/docker-compose.yml) runs Ollama (`engine`), Open WebUI (`chat`) and n8n (`agent`) on space-needle, CPU-only. The [briefing workflow](../../services/sputnik/workflows/briefing.md) summarizes Gmail/Calendar into a LAN page.

| Host path | Contents |
|---|---|
| `/mammoth/sputnik/models` | Ollama weights |
| `/opt/sputnik/open-webui` | Users and chats |
| `/opt/sputnik/n8n` | Container home; `.n8n/` holds the DB and encrypted credentials |
| `/opt/sputnik/briefing` | Published `latest.json` |

Back up the data **and** `N8N_ENCRYPTION_KEY`; without the key stored credentials are useless.

Ollama has no auth: host port is loopback-only, containers reach `ollama:11434`, no Caddy route. Keep Sputnik, n8n and briefing off the tunnel.

## Setup

1. Copy [.env.example](../../services/sputnik/.env.example); generate WebUI and n8n keys with `openssl rand -hex 32`.
2. Pull the base model and build the persona from [Modelfile.assistant](../../services/sputnik/Modelfile.assistant):

   ```bash
   sudo docker exec -it ollama ollama pull qwen3:30b-a3b
   sudo docker exec -i ollama ollama create sputnik-assistant \
     -f /dev/stdin < services/sputnik/Modelfile.assistant
   ```

3. Create the Open WebUI account at `https://sputnik.loft.hsimah.com`, then disable signup and recreate. Create the n8n owner at `https://n8n.loft.hsimah.com`.
4. Google OAuth (below), then [import the workflow](../../services/sputnik/workflows/briefing.md).
5. Set the [briefing password](mushr.md#briefing-mount-and-password) and Homepage credential.

Rebuild the derived model after editing the Modelfile.

## Google OAuth

Enable Gmail and Calendar APIs, create a web OAuth client with callback `https://n8n.loft.hsimah.com/rest/oauth2-credential/callback`, and use n8n's generic Google OAuth2 credential with only:

```text
https://www.googleapis.com/auth/gmail.readonly
https://www.googleapis.com/auth/calendar.readonly
```

Read-only is deliberate: a local model reading an untrusted inbox is a prompt-injection surface. Don't widen scopes without asking; `gmail.compose` can also **send**. Testing-mode consent screens expire tokens.

## Performance

`qwen3:30b-a3b` on the i9-12900H: ~14.5 tok/s generation at 12 threads, ~20 GB resident, ~45 s to first token. The Modelfile uses 12 threads and 16k context; `OLLAMA_KEEP_ALIVE=-1` keeps it loaded. Re-measure with `bash services/sputnik/bench.sh sputnik-assistant`.

## Troubleshooting

- **Missing models**: `sudo docker exec ollama ollama list`; consumers must use `http://ollama:11434`.
- **n8n home errors**: mount all of `/home/node` and keep explicit `HOME`/`N8N_USER_FOLDER`; mounting only `.n8n` breaks cache paths.
- **Briefing write denied**: keep `/briefing` in `N8N_RESTRICT_FILE_ACCESS_TO`; check the mount's ownership.
- **Briefing stale**: check the workflow is published and executing. `active: true` in an export doesn't mean it's running.
- **Profile errors**: engine consumers use `depends_on` with `required: false` so profiles validate independently; keep it.
- The JSON write isn't atomic; a parse error during publication is transient.
