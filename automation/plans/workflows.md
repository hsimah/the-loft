# Custom AI workflows

**n8n already runs.** Sputnik's `agent` profile runs n8n on space-needle with the briefing workflow, against CPU Ollama ([Sputnik](../../docs/services/sputnik.md)). Item 5 is therefore mostly repointing and conventions, not a new tool.

## Plan

- **Keep n8n on space-needle** as the orchestrator. Its state and credentials live with the fleet's storage; helarctos stays compute-only.
- **Point model calls at llama-swap**: an OpenAI-compatible credential with base `http://helarctos:8080/v1` and the API key, then retire Ollama on space-needle (D21). Open WebUI moves first ([chat](#chat)).
- **Workflows as code**: export each workflow to `services/sputnik/workflows/<name>.json` with a `.md` beside it, as [briefing](../../services/sputnik/workflows/briefing.md) does.
- **Backups**: n8n data plus `N8N_ENCRYPTION_KEY` ([backups](backups.md), [#108](https://github.com/hsimah/the-loft/issues/108)).

Planned workflows: the [intake](intake.md) router, wiki inbox filing, calendar extraction and [reports](calendar.md#reports), recipe imports.

## Moving n8n to llama-swap

Phase 3, once D18 settles which models stay resident. No Compose change: n8n already resolves `helarctos` through Mushr DNS.

1. Add an OpenAI credential in n8n: key `LLAMA_SWAP_API_KEY`, Base URL `http://helarctos:8080/v1`.
2. The [briefing](../../services/sputnik/workflows/briefing.md) uses `sputnik-assistant`, an Ollama model built from [Modelfile.assistant](../../services/sputnik/Modelfile.assistant); llama-swap has no equivalent. Replace the Ollama Chat Model node with an OpenAI Chat Model node, copy the Modelfile's `SYSTEM` prompt into the LLM Chain's system message, and set temperature 0.3 and top_p 0.9 in the node options.
3. Pick a resident model so the 6-hourly run never swaps out a coding job's model.
4. Export to `briefing.json`, update `briefing.md`, and run its post-change checks (normal mail, empty inbox, phishing). Then retire Ollama and the Modelfile (D21).

## Chat

Done (D0, 2026-10-25): Open WebUI at `https://sputnik.loft.hsimah.com` uses llama-swap; current state is on the [Sputnik page](../../docs/services/sputnik.md#chat-on-the-gpu). Remaining:

- Remove the Ollama connection when Ollama is retired (D21).
- Vault documents never go into Open WebUI: its uploads and knowledge bases keep copies outside the vault. Use Paperless's document chat for those.
- Later: Open WebUI tools that read the wiki and calendar.

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
