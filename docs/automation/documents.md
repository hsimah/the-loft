# Documents: Paperless in Mercurius

The document half of [Mercurius](mercurius.md): financial, medical and personal records, and any other document, in Paperless-ngx on the encrypted volume. Every document is searchable by content; the original is kept forever so its text can be re-read as models improve. Paperless with standard OCR is live in Mercurius ([service page](../services/mercurius.md)). This page holds the OCR, intake and backup work still to come.

## Stack

| Piece | Proposed | Notes |
|---|---|---|
| Archive | [Paperless-ngx](https://docs.paperless-ngx.com) 3.x | Keeps the original next to its text. 3.0 (July 2026) added opt-in AI: suggested title, tags, correspondent, type, dates; document chat; similar documents. `PAPERLESS_AI_LLM_BACKEND=openai-like` points it at llama-swap ([setup guide](https://wz-it.com/en/blog/paperless-ngx-ai-setup/)) |
| Helpers | Postgres, Redis, Tika, Gotenberg | Tika and Gotenberg let it consume `.eml` and office files from [intake](intake.md) |
| AI OCR | [paperless-gpt](https://github.com/icereed/paperless-gpt) | Vision-model OCR for messy scans via an OpenAI-compatible base URL; tag-triggered. **No login of its own**: anyone who reaches it can rewrite documents, so it stays on the vault's internal network with no Caddy route |
| Mail fetcher | `mercurius-fetch`, a small IMAP fetch container | Phase 4; see [intake](intake.md#vault-fetcher) |

Not Paperless-AI: unmaintained since March 2026, and Paperless's built-in AI covers it.

Paperless 3.3's AI does not fill custom fields and takes no custom prompts. Due and expiry dates for the [Janus](janus.md) therefore come from the linker job below, or from paperless-gpt if its pinned version supports custom fields.

## Isolation

- **Shared with the wiki.** Paperless and SilverBullet share the group, the encrypted volume and its internal networks ([Mercurius](../services/mercurius.md#isolation)). Wiki pages may quote documents. One shared household archive (D4); Paperless permissions can split it later.
- **Encrypted at rest** (D5): LUKS2 on a 250 GB LVM volume on the NVMe, unlocked by hand after each boot. Everything, including Postgres with the OCR text, is on it, and nothing in the group starts while it is locked.
- **One route out.** Paperless and paperless-gpt reach `helarctos:8080` only, one way, through a bridge and nftables rule ([model egress](../services/mercurius.md#model-egress)); the rest of the group is on internal networks. The mail fetcher is the one exception, in its own container.
- **Read from outside.** Open WebUI and n8n read documents through Caddy with an API token ([chat and n8n access](mercurius.md#chat-and-n8n-access)); what they store is outside the vault, an accepted risk.
- **No side doors.** Only the Paperless and SilverBullet UIs are routed through Caddy, LAN and Tailscale only. Never on the tunnel.
- **AI suggests, you approve.** Suggestions and review tags, never silent overwrites.
- **The AI machine stores nothing.** Documents pass through helarctos in memory. llama-swap at `logLevel: info` does not log request bodies (checked against a real ID document; see [the runbook](../services/mercurius.md#built-in-ai)), and the hop is plain HTTP on the LAN.
- **Local models only**, never Claude.

## Getting documents in

Every document goes to Paperless, not into wiki attachments: the wiki holds notes and links, and SilverBullet does not index text inside images or PDFs.

1. **Phone or scanner**: upload through the web UI or a Paperless mobile app (over Tailscale off-LAN), or a scanner writing to the consume folder. Which scanner, if any, is open.
2. **OneDrive remainder**: retarget [onedrive-pull.sh](../../control-plane/onedrive-pull.sh) at a vault staging directory, then triage: documents to Paperless, everything else to general files. OneDrive is paid until May 2027.
3. **Email**: forward to the vault address ([intake](intake.md)).

## Scanning, OCR and re-checking

Every original is kept, so text can be re-read as models improve.

```mermaid
flowchart LR
  new[New scan] --> std[Standard OCR] --> vlm[VLM OCR: paperless-gpt] --> hist[(OCR history)]
  hist --> due{Due for re-check?}
  due -- monthly job --> reread[Re-read with current model] --> diff{Differs?}
  diff -- small --> update[Update text]
  diff -- large --> flag[Tag ocr-review, notify]
```

Three small custom pieces, in bash per repo rules:

- **OCR history table**: one row per reading: document, model and version, prompt, date, text.
- **Re-check job**: re-reads documents not checked for N months (D7) or read by an older model. Small differences update automatically; large ones get `ocr-review` and an [ntfy](shared-services.md) notice, because a disagreement between two readings is where mistakes hide.
- **Linker job**: proposes summaries, tags, links and custom-field dates for new documents, as suggestions.

Batch work follows the [GPU sharing rules](models.md#sharing-the-gpu).

## LLM improvements

Possible jobs; none started.

- **Second-pass OCR failures.** After the bulk import, 26 documents carry `paperless-gpt-failed`, and the logs from that run have rotated out. Three are text files (CSV, TXT) with no page to render: keep non-image types out of the tag. The rest are born-digital bank statements and 1099s of 2–6 dense pages. Candidates: glm-ocr's `--ctx-size 16384` is too small for a dense page's image plus transcription, or the PDFs are encrypted (one, an `International_Application` PDF, has no page count in Paperless). Fix by raising the context, or skip the second pass for born-digital PDFs whose text layer is already exact. Document 114 is queued again as a test.
- **paperless-gpt logs.** At `LOG_LEVEL: info` the container writes large serialized text to its Docker log, probably document text, under `/var/lib/docker` on the unencrypted root disk (up to 30 MB). Try `warn`, recheck, and correct the [log check](../services/mercurius.md#built-in-ai).
- **Built-in AI.** Try suggestions, chat and similar documents on the imported archive ([built-in AI](../services/mercurius.md#built-in-ai)).
- **Expiry dates.** Fill an `Expiry` custom field (passports, licences) for [Janus](janus.md) reminders, through the linker job above or paperless-gpt.
- **OCR scoring.** Score `glm-ocr` against `paddleocr-vl` on a sample of real documents ([roadmap](roadmap.md#phase-7--ai-upkeep)).

## Backups

Built but shelved (2026-10-26): `document_exporter` output plus a Postgres dump, in an encrypted restic repository of its own. After the move the same job also takes the SilverBullet folder ([runbook](../operations/backups.md)). See [backups](backups.md).

## Open questions

- D7: re-check interval: 3, 6 or 9 months?
- D8: who reviews flagged documents, and how are you notified?
- Is there a scanner with a document feeder, or is the phone the scanner?
