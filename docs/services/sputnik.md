# Sputnik — local assistant

[Compose](../../services/sputnik/docker-compose.yml) runs Open WebUI (`chat`) and n8n (`agent`) on space-needle and llama-swap (`gpu`) on helarctos. Both apps take their models from llama-swap ([chat](#chat-on-the-gpu)); space-needle runs no inference.

| Host path | Contents |
|---|---|
| `/opt/sputnik/open-webui` | Users and chats |
| `/opt/sputnik/n8n` | Container home; `.n8n/` holds the DB and encrypted credentials |

Back up the data **and** `N8N_ENCRYPTION_KEY`; without the key stored credentials are useless.

Keep Sputnik and n8n off the tunnel.

## Setup

1. Copy [.env.example](../../services/sputnik/.env.example); generate WebUI and n8n keys with `openssl rand -hex 32`. Set `LLAMA_SWAP_API_KEY` to helarctos's value.
2. Create the Open WebUI account at `https://sputnik.loft.hsimah.com`, then disable signup and recreate. Create the n8n owner at `https://n8n.loft.hsimah.com`.
3. Google OAuth (below) when a workflow needs it.

## Google OAuth

Enable Gmail and Calendar APIs, create a web OAuth client with callback `https://n8n.loft.hsimah.com/rest/oauth2-credential/callback`, and use n8n's generic Google OAuth2 credential with only:

```text
https://www.googleapis.com/auth/gmail.readonly
https://www.googleapis.com/auth/calendar.readonly
```

Read-only is deliberate: a model reading an untrusted inbox is a prompt-injection surface. Don't widen scopes without asking; `gmail.compose` can also **send**. Testing-mode consent screens expire tokens.

## GPU engine on helarctos

The `gpu` profile runs llama-swap on [helarctos](../hosts/helarctos.md). It starts llama.cpp's `llama-server` (Vulkan) for whichever model a request names, and serves the OpenAI and Anthropic Messages APIs on `:8080`. The evaluation set for [#149](https://github.com/hsimah/the-loft/issues/149) is Qwen3.8-Flash-Next, gpt-oss-120b and Qwen3.5-122B-A10B. Each needs most of the GTT, so one is loaded at a time and a request for another swaps it. The runner takes one job at a time to match. Measured from disk with a short prompt (2026-10-24):

| Model | Swap and load | Generation |
|---|---|---|
| gpt-oss-120b (MXFP4) | 10 s warm, 23–25 s cold | 51 tok/s |
| Qwen3.5-122B-A10B (UD-Q4_K_XL) | 36 s | 23 tok/s |
| Qwen3.8-Flash-Next (UD-IQ4_XS) | 34 s | 26 tok/s; about half the reported speed, possibly the IQ quant on Vulkan |

- Models: [llama-swap.yaml](../../services/sputnik/llama-swap.yaml). llama-swap watches it, but the file is a single bind mount: after a `git pull`, recreate the container (`sudo docker compose -f services/sputnik/docker-compose.yml up -d --force-recreate llama-swap`).
- Weights: `/den/sputnik/models` (`/models` in the container). [fetch-model.sh](../../services/sputnik/fetch-model.sh) downloads them from Hugging Face, resumably and SHA-256 checked; rerun it after an interruption. Run it as adminhabl in tmux:

  ```bash
  services/sputnik/fetch-model.sh unsloth/Qwen3.8-Flash-Next-GGUF UD-IQ4_XS/ qwen3.8-flash-next
  services/sputnik/fetch-model.sh ggml-org/gpt-oss-120b-GGUF gpt-oss-120b-MXFP4 gpt-oss-120b
  services/sputnik/fetch-model.sh unsloth/Qwen3.5-122B-A10B-GGUF UD-Q4_K_XL/ qwen3.5-122b-a10b
  ```

- Auth: every endpoint except `/health` requires `LLAMA_SWAP_API_KEY` as a bearer token, including the UI and logs. LAN only; no Caddy route and never on the tunnel.
- Claude Code against a local model. It assumes 200k for model IDs it doesn't know, so give it llama-swap's `--ctx-size`, or long sessions overflow before Claude Code compacts:

  ```bash
  ANTHROPIC_BASE_URL=http://helarctos:8080 ANTHROPIC_AUTH_TOKEN=<key> CLAUDE_CODE_MAX_CONTEXT_TOKENS=131072 \
    claude -p --model gpt-oss-120b 'say ok'
  ```

Set `COMPOSE_PROFILES=gpu` in helarctos's `services/sputnik/.env`; the other profiles stay on space-needle.

## OCR models

`glm-ocr` (MIT) and `paddleocr-vl` (Apache 2.0) are small vision models for [Plutus](plutus.md) and [Mercurius](mercurius.md), about 1.5–2 GB each with their vision projector. They sit in llama-swap's persistent `ocr` group, so they stay loaded beside whichever large model is running and a request for one never swaps the other out. Both are configured and not yet downloaded or measured; the entries and `--ctx-size 16384` are starting values.

Each model is a language GGUF plus a separate `--mmproj` vision projector, so each is fetched in two calls, into one directory:

```bash
services/sputnik/fetch-model.sh ggml-org/GLM-OCR-GGUF GLM-OCR-Q8_0 glm-ocr
services/sputnik/fetch-model.sh ggml-org/GLM-OCR-GGUF mmproj-GLM-OCR-Q8_0 glm-ocr
services/sputnik/fetch-model.sh PaddlePaddle/PaddleOCR-VL-1.5-GGUF PaddleOCR-VL-1.5 paddleocr-vl-1.5
```

The last call matches both the model and its `PaddleOCR-VL-1.5-mmproj.gguf` projector. Then recreate the container (above) and try each against the same scan:

```bash
curl -s http://localhost:8080/v1/chat/completions -H "Authorization: Bearer $LLAMA_SWAP_API_KEY" -H 'Content-Type: application/json' \
  -d "{\"model\":\"glm-ocr\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"Read all the text on this page.\"},{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/png;base64,$(base64 -w0 page.png)\"}}]}]}"
```

## Chat on the GPU

Open WebUI reaches llama-swap at `http://helarctos:8080/v1`, keyed with `LLAMA_SWAP_API_KEY`; space-needle's `.env` needs the same value as helarctos's. The model list comes from llama-swap, so a model added to [llama-swap.yaml](../../services/sputnik/llama-swap.yaml) appears without changes here.

- The Compose variables only seed a fresh install. Open WebUI stores connections in its database after the first start, and the database wins: change connections in Admin → Settings → Connections.
- A request for a model that isn't loaded waits for the swap (10–36 s), and competes with Kennl runner jobs for the one loaded model.

## Troubleshooting

- **Missing models**: `curl -H "Authorization: Bearer $LLAMA_SWAP_API_KEY" http://helarctos:8080/v1/models`; consumers use `http://helarctos:8080/v1`.
- **n8n home errors**: mount all of `/home/node` and keep explicit `HOME`/`N8N_USER_FOLDER`; mounting only `.n8n` breaks cache paths.
