# Custom AI workflows

**n8n already runs.** Sputnik's `agent` profile runs n8n on space-needle with no workflows yet, against llama-swap ([Sputnik](../../docs/services/sputnik.md)). Item 5 is therefore conventions, not a new tool.

## Plan

- **Keep n8n on space-needle** as the orchestrator. Its state and credentials live with the fleet's storage; helarctos stays compute-only.
- **Model calls go to llama-swap** through an OpenAI credential (`helarctos llama-swap`, base `http://helarctos:8080/v1`). Ollama is retired (D21).
- **Workflows as code**: export each workflow to `services/sputnik/workflows/<name>.json` with a `.md` beside it.
- **Backups**: n8n data plus `N8N_ENCRYPTION_KEY` ([backups](backups.md), [#108](https://github.com/hsimah/the-loft/issues/108)).

Planned workflows: the [intake](intake.md) router, wiki inbox filing, calendar extraction and [reports](janus.md#reports), recipe imports.

## Chat

Done (D0, 2026-10-25): Open WebUI at `https://sputnik.loft.hsimah.com` uses llama-swap only; current state is on the [Sputnik page](../../docs/services/sputnik.md#chat-on-the-gpu). Remaining:

- Vault documents never go into Open WebUI: its uploads and knowledge bases keep copies outside the vault. Use Paperless's document chat for those.
- Later: Open WebUI tools that read the wiki and calendar.
- Later: [web search and research](#web-search-and-research).

### Web search and research

Not scheduled. Open WebUI has no search backend, so chat models cannot reach the web.

1. **Search toggle and weather.** SearXNG (D23) behind Open WebUI's built-in web search: one search round per message, no model tool calling. Weather as a tool on Open-Meteo (no key), not a search.
2. **Tool calling in chat.** The model decides when to search and fetch, in a loop. Needs [#149](https://github.com/hsimah/the-loft/issues/149)'s model choice.
3. **Deep research.** Multi-step search to a cited report, run as a queued n8n or [#152](https://github.com/hsimah/the-loft/issues/152) job, not live chat. Page dumps make long prompts, so it obeys the [GPU sharing rules](models.md#sharing-the-gpu).

Constraints:

- **Web and private data never meet.** A model or chat with web tools gets no wiki or calendar tools, memories or knowledge bases, and vice versa. Fetched pages can carry prompt injection; arbitrary URL fetches and rendered markdown images are exfiltration channels.
- **No LAN fetches.** Open WebUI's fetcher sits on `loft-proxy` with LAN DNS. Keep local-address fetching off: `ENABLE_LOCAL_WEB_FETCH` (the old name `ENABLE_RAG_LOCAL_WEB_FETCH` is a deprecated alias), default false in 0.12.4 (read in the source). While off, every address a fetched hostname resolves to must be globally routable, which rejects LAN, Tailscale and loopback addresses; redirects are checked the same way. Do not set either variable in Sputnik's `.env`. Confirm on the running container, then probe the real targets:

  ```bash
  sudo docker exec open-webui env | grep -i LOCAL_WEB_FETCH    # expect no output
  sudo docker exec open-webui python -c "
  from open_webui.retrieval.web.utils import validate_url
  for u in ['http://helarctos:8080', 'https://kennl.loft.hsimah.com', 'http://192.168.86.1', 'https://example.com']:
      try: print(u, validate_url(u))
      except Exception as e: print(u, 'BLOCKED')"
  ```

  The first three must print `BLOCKED` and the last `True`. Then repeat once through the chat's own URL fetch, since that is the path a model uses. The fetcher still shares `loft-proxy` with Caddy, so a container escape is not covered; the setting limits what a fetched URL can reach, not the container's network.
- **Tools are code.** Open WebUI tools run Python inside the container: write and review our own, install no community tools.
- **Queries leave the LAN.** SearXNG forwards them to upstream engines from the home IP; paid APIs log them.

## Shell steps

yt-dlp, ffmpeg and whisper don't belong in the n8n container. D17 options:

| Option | For | Against |
|---|---|---|
| **Media worker on helarctos** (recommended): [`webhook`](https://github.com/adnanh/webhook) mapping token-authenticated HTTP calls to bash scripts in this repo, as a Sputnik profile (`sputnik-worker`) | Bash, as the repo prefers; runs next to the GPU; stateless | One more small container |
| Custom n8n image with Execute Command enabled | No new service | Shell inside the process that reads mail; image to maintain |
| [Windmill](https://www.windmill.dev) | Native bash scripts, flows, workers on other hosts | A second workflow engine plus its Postgres |

Revisit Windmill only if n8n's JavaScript code nodes become the bottleneck.

## Rules

- Every model call goes through llama-swap and obeys the [GPU sharing rules](models.md#sharing-the-gpu).
- Untrusted text (mail, scraped pages, captions) goes only to models without tools, and their output goes to a review queue. Exception: [web research](#web-search-and-research) models, whose only tools are search and fetch.
- n8n stays off the tunnel.
