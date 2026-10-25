# Custom AI workflows

**n8n already runs.** Sputnik's `agent` profile runs n8n on space-needle with the briefing workflow, against CPU Ollama ([Sputnik](../../docs/services/sputnik.md)). Item 5 is therefore mostly repointing and conventions, not a new tool.

## Plan

- **Keep n8n on space-needle** as the orchestrator. Its state and credentials live with the fleet's storage; helarctos stays compute-only.
- **Point model calls at llama-swap**: an OpenAI-compatible credential with base `http://helarctos:8080/v1` and the API key, then retire Ollama on space-needle (D21). Open WebUI moves first ([chat](#chat)).
- **Workflows as code**: export each workflow to `services/sputnik/workflows/<name>.json` with a `.md` beside it, as [briefing](../../services/sputnik/workflows/briefing.md) does.
- **Backups**: n8n data plus `N8N_ENCRYPTION_KEY` ([backups](backups.md), [#108](https://github.com/hsimah/the-loft/issues/108)).

Planned workflows: the [intake](intake.md) router, wiki inbox filing, calendar extraction and [reports](calendar.md#reports), recipe imports.

## Chat

D0, to do now, ahead of the phases. Open WebUI (Sputnik `chat`, `https://sputnik.loft.hsimah.com`) is the prompt portal. It currently uses CPU Ollama; point it at llama-swap instead.

- Add an OpenAI-compatible connection: base `http://helarctos:8080/v1`, key `LLAMA_SWAP_API_KEY`. llama-swap's `/v1/models` fills the model list.
- Open WebUI's connection variables (`OPENAI_API_BASE_URL(S)`, `OPENAI_API_KEY(S)`) are persistent config: after the first start the database wins over the environment. On this existing install, add the connection in Admin → Settings → Connections, or set it in Compose and `.env.example` for fresh installs and in the UI as well.
- The container resolves through Mushr's dnsmasq (`dns: [192.168.86.28]`); check it resolves `helarctos`, otherwise use `192.168.86.21`.
- Keep the Ollama connection until the new one is proven; removing it is D21.
- Expect a 10–36 s wait when the request names a model that isn't loaded, and contention with overnight coding jobs (D18).
- Vault documents never go into Open WebUI: its uploads and knowledge bases keep copies outside the vault. Use Paperless's document chat for those.
- Update the [Sputnik page](../../docs/services/sputnik.md) once it's live.

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
- Untrusted text (mail, scraped pages, captions) goes only to models without tools, and their output goes to a review queue.
- n8n stays off the tunnel.
