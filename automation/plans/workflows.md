# Custom AI workflows

**n8n already runs.** Sputnik's `agent` profile runs n8n on space-needle with no workflows yet, against llama-swap ([Sputnik](../../docs/services/sputnik.md)). Item 5 is therefore conventions, not a new tool.

## Plan

- **Keep n8n on space-needle** as the orchestrator. Its state and credentials live with the fleet's storage; helarctos stays compute-only.
- **Model calls go to llama-swap** through an OpenAI credential (`helarctos llama-swap`, base `http://helarctos:8080/v1`). Ollama is retired (D21).
- **Workflows as code**: export each workflow to `services/sputnik/workflows/<name>.json` with a `.md` beside it.
- **Backups**: n8n data plus `N8N_ENCRYPTION_KEY` ([backups](backups.md), [#108](https://github.com/hsimah/the-loft/issues/108)).

Planned workflows: the [intake](intake.md) router, wiki inbox filing, calendar extraction and [reports](calendar.md#reports), recipe imports.

## Chat

Done (D0, 2026-10-25): Open WebUI at `https://sputnik.loft.hsimah.com` uses llama-swap only; current state is on the [Sputnik page](../../docs/services/sputnik.md#chat-on-the-gpu). Remaining:

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
