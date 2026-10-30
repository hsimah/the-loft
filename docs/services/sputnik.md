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

The `gpu` profile runs llama-swap on [helarctos](../hosts/helarctos.md). It starts llama.cpp's `llama-server` (Vulkan) for whichever model a request names, and serves the OpenAI and Anthropic Messages APIs on `:8080`. The household models stay resident (D18, [models](../automation/models.md#sharing-the-gpu)). The large models, gpt-oss-120b and Qwen3.5-122B-A10B, load on demand into the rest of the GTT, one at a time; a request for the other swaps it. Both fit beside the household set ([GTT use](../automation/models.md#sharing-the-gpu)). Measured from disk with a short prompt (2026-10-24, before the household set was resident):

| Model | Swap and load | Generation |
|---|---|---|
| gpt-oss-120b (MXFP4) | 10 s warm, 23–25 s cold | 51 tok/s |
| Qwen3.5-122B-A10B (UD-Q4_K_XL) | 36 s | 23 tok/s |

- Models: [llama-swap.yaml](../../services/sputnik/llama-swap.yaml). llama-swap watches it, but the file is a single bind mount: after a `git pull`, recreate the container (`sudo docker compose -f services/sputnik/docker-compose.yml up -d --force-recreate llama-swap`).
- Weights: `/den/sputnik/models` (`/models` in the container). [fetch-model.sh](../../services/sputnik/fetch-model.sh) downloads them from Hugging Face, resumably and SHA-256 checked; rerun it after an interruption. Run it as adminhabl in tmux:

  ```bash
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

`glm-ocr` (MIT) and `paddleocr-vl` (Apache 2.0) are small vision models for Paperless's [second-pass OCR](mercurius.md#second-pass-ocr), about 1.5–2 GB each with their vision projector. They sit in llama-swap's persistent `household` group with the text and embedding models, so they stay loaded beside whichever large model is running and a request for one never swaps the others out. Both are downloaded and answer on helarctos; neither is benchmarked yet, and the entries and `--ctx-size 16384` are starting values.

Each model is a language GGUF plus a separate `--mmproj` vision projector, so each is fetched in two calls, into one directory:

```bash
services/sputnik/fetch-model.sh ggml-org/GLM-OCR-GGUF GLM-OCR-Q8_0 glm-ocr
services/sputnik/fetch-model.sh ggml-org/GLM-OCR-GGUF mmproj-GLM-OCR-Q8_0 glm-ocr
services/sputnik/fetch-model.sh PaddlePaddle/PaddleOCR-VL-1.5-GGUF PaddleOCR-VL-1.5 paddleocr-vl-1.5
```

The last call matches both the model and its `PaddleOCR-VL-1.5-mmproj.gguf` projector. Then recreate the container (above). Each model expects a fixed task prompt, not a free-form instruction: `Text Recognition:` for `glm-ocr`, `OCR:` for `paddleocr-vl`. Both are built for a two-stage pipeline (layout analysis, then recognition of each region), so a whole page sent straight in is a rougher test than what paperless-gpt will do. Try each against the same page image (render a PDF page first, for example with `pdftoppm -png -r 150 -f 1 -l 1 -singlefile`):

```bash
model=glm-ocr prompt='Text Recognition:'     # or: model=paddleocr-vl prompt='OCR:'
base64 -w0 page.png > /tmp/page.b64
jq -n --arg m "$model" --arg p "$prompt" --rawfile img /tmp/page.b64 \
  '{model:$m,messages:[{role:"user",content:[{type:"text",text:$p},{type:"image_url",image_url:{url:("data:image/png;base64,"+$img)}}]}]}' > /tmp/ocr-req.json
time curl -fsS -H "Authorization: Bearer $LLAMA_SWAP_API_KEY" -H 'Content-Type: application/json' \
  -d @/tmp/ocr-req.json http://localhost:8080/v1/chat/completions | jq -r '.choices[0].message.content, .usage'
rm -f /tmp/page.b64 /tmp/ocr-req.json
```

## Paperless models

Paperless's [built-in AI](mercurius.md#built-in-ai) (suggestions and chat) uses two more models through the same gateway:

| Model | Role | Size | Group | Licence |
|---|---|---|---|---|
| `qwen3.6-35b-a3b` (UD-Q4_K_XL) | Suggestions and chat | 22 GB | `household`: resident; loads once after llama-swap starts (23–36 s) | Apache 2.0 |
| `embeddinggemma` (300M, Q8_0) | Embeddings for chat retrieval and suggestion context | 0.3 GB | `household`: resident | Gemma terms of use |

Fetch, then recreate the container (above):

```bash
services/sputnik/fetch-model.sh unsloth/Qwen3.6-35B-A3B-GGUF Qwen3.6-35B-A3B-UD-Q4_K_XL qwen3.6-35b-a3b
services/sputnik/fetch-model.sh ggml-org/embeddinggemma-300M-GGUF embeddinggemma-300M-Q8_0 embeddinggemma
```

Check embeddings return a vector:

```bash
curl -s http://localhost:8080/v1/embeddings -H "Authorization: Bearer $LLAMA_SWAP_API_KEY" -H 'Content-Type: application/json' \
  -d '{"model":"embeddinggemma","input":"a council rates notice"}' | jq '.data[0].embedding | length'
```

## Chat on the GPU

Open WebUI reaches llama-swap at `http://helarctos:8080/v1`, keyed with `LLAMA_SWAP_API_KEY`; space-needle's `.env` needs the same value as helarctos's. The model list comes from llama-swap, so a model added to [llama-swap.yaml](../../services/sputnik/llama-swap.yaml) appears without changes here.

- The Compose variables only seed a fresh install. Open WebUI stores connections in its database after the first start, and the database wins: change connections in Admin → Settings → Connections.
- The household models are resident; a request for a large model that isn't loaded waits for the swap (10–36 s).

## Household tools

Open WebUI chats with the wiki and documents through n8n ([plan](../automation/mercurius.md#chat-and-n8n-access)). Live for documents (2026-10-30); the wiki tools are next.

- **n8n:** the `Paperless` workflow is an MCP Server Trigger at path `mercurius-documents` (bearer credential `Open WebUI MCP`) with two HTTP Request Tools, `search_documents` and `read_document`, calling `https://paperless.loft.hsimah.com/api` as the read-only Paperless user `sputnik` (credential `Paperless sputnik (read-only)`). Successful and manual executions are not saved.
- **Open WebUI:** Admin → Settings → Integrations → External Tool Servers: MCP (Streamable HTTP) at `http://n8n:5678/mcp/mercurius-documents`, Bearer, ID `mercurius-documents`. Direct Integrations stays off, so users cannot attach their own tool servers.
- **Household model:** [household.json](../../services/sputnik/open-webui/household.json), exported from Workspace → Models; import it there to rebuild. `builtin_tools: false` keeps web, code, image, memory and notes tools out of its chats.

## Troubleshooting

- **Missing models**: `curl -H "Authorization: Bearer $LLAMA_SWAP_API_KEY" http://helarctos:8080/v1/models`; consumers use `http://helarctos:8080/v1`.
- **n8n home errors**: mount all of `/home/node` and keep explicit `HOME`/`N8N_USER_FOLDER`; mounting only `.n8n` breaks cache paths.
