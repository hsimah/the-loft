# Automation plans

Planning notes for the household AI services: apps and data on [space-needle](../../docs/hosts/space-needle.md), inference on [helarctos](../../docs/hosts/helarctos.md). **Everything here is proposed** unless a line says otherwise. Once something is built, its current state moves to `docs/services/<name>.md` and the plan page shrinks to the remaining work; delete a page when nothing is left.

These pages replace the [Home Second Brain proposal](https://claude.ai/artifact/EbMpmFyehGEkf5CyRf4reR) doc; its content is in [Mercurius](mercurius.md), [documents](documents.md) and [models](models.md).

## Use cases

| # | Use case | State | Page |
|---|---|---|---|
| 0 | Chat portal: Open WebUI on the GPU | Live | [workflows](workflows.md#chat) |
| 1 | Agentic coding | In progress ([#155](https://github.com/hsimah/the-loft/issues/155)) | [coding-agents](coding-agents.md) |
| 2a | Mercurius: wiki and documents on the encrypted volume | Wiki and Paperless live separately (Mercurius, Plutus); merge proposed; backup shelved | [Mercurius](mercurius.md) |
| 2b | Documents: Paperless OCR, re-checks, intake | Paperless and second-pass OCR live | [documents](documents.md) |
| 3 | Janus: calendar, reminders and reports | Proposed | [Janus](janus.md) |
| 4 | Ceres: recipes from email, photos and reels | Proposed | [Ceres](ceres.md) |
| 5 | Custom AI workflows | n8n already runs (CPU) | [workflows](workflows.md) |

Cross-cutting: [shared services](shared-services.md) · [email intake](intake.md) · [off-site backups](backups.md) · [models and GPU sharing](models.md) · [Tailscale](tailscale.md).

Planning: [roadmap](roadmap.md) · [decisions](decisions.md) · [names](names.md).

## How the pieces connect

```mermaid
flowchart LR
  mail[Curated email] --> intake[Intake mailbox]
  phone[Phone: scans, photos, links] --> vault & recipes & wiki
  intake --> n8n[n8n router]
  intake --> fetch[mercurius-fetch]
  fetch --> vault[Mercurius: Paperless-ngx]
  chat[Open WebUI] & n8n <--> wiki[Mercurius: SilverBullet] & vault
  n8n --> cal[Janus: Radicale]
  n8n --> recipes[Ceres: Mealie]
  vault -- dates, titles only --> cal
  cal & wiki --> report[Morning report]
  report --> ntfy[ntfy push] & page[Report page]
  vault & wiki & recipes & n8n & report --> llm[llama-swap on helarctos]
  n8n --> worker[Media worker on helarctos]
  vault & wiki & cal & recipes --> backup[(Google Drive, encrypted)]
```

Viking and fjord are not needed: every piece here wants space-needle's storage or helarctos's GPU, and Viking is the DMZ.

## Conventions

- One topic per page. Decisions live in [decisions.md](decisions.md) with an ID; topic pages refer to the ID instead of repeating the options.
- Link to Compose, host.conf and docs for exact images, ports and paths; don't copy them here.
- Label anything not checked on a live host as unverified.
