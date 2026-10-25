# Decisions

Register of open choices. When one is made, set Status to the decision and date, update the topic page, and drop the losing options from it.

| ID | Decision | Recommendation | Status | Page | Needed by |
|---|---|---|---|---|---|
| D0 | Chat portal | Open WebUI on llama-swap now, ahead of phase 3 | Done 2026-10-25 | [workflows](workflows.md#chat) | Now |
| D1 | Service names | Pick from the proposals | Decided 2026-10-25: Mercurius (wiki), Plutus (vault), Janus (calendar), Ceres (recipes) | [names](names.md) | Phase 1 |
| D2 | Wiki editor | SilverBullet; Obsidian optional on the same repo | Decided 2026-10-25: SilverBullet | [Mercurius](mercurius.md) | Phase 1 |
| D3 | Wiki history | Sidecar autocommit to a private Forgejo repo | Open | [Mercurius](mercurius.md) | Phase 1 |
| D9 | Off-LAN access | Tailscale on phones and laptops; nothing on the tunnel | Open | [shared-services](shared-services.md) | Phase 1 |
| D10 | Off-site backup tool | restic through rclone to Google Drive | Open | [backups](backups.md) | Phase 1 |
| D11 | Backup key custody | Password manager + printed sheet in the safe; both of you can restore | Open | [backups](backups.md) | Phase 1 |
| D19 | Planning pages after the wiki is live | Stay in this repo | Open | [Mercurius](mercurius.md) | Phase 1 |
| D4 | Vault areas | Shared to start; Paperless permissions can split later | Decided 2026-10-25: shared | [Plutus](plutus.md) | Phase 2 |
| D5 | Vault encryption at rest | LUKS volume unlocked by hand after each boot. A keyfile on the root disk only protects a stolen data disk | Decided 2026-10-25: LUKS, manual unlock after each boot | [Plutus](plutus.md) | Phase 2 |
| D6 | First records in | Your call: tax and financial, medical, or IDs | Open | [Plutus](plutus.md) | Phase 2 |
| D18 | GPU residency and night split | Keep the household set resident; prefer a coder that fits beside it; household batch 01:00–02:30 | Open; depends on [#149](https://github.com/hsimah/the-loft/issues/149) | [models](models.md#sharing-the-gpu) | Phase 3 |
| D21 | Ollama on space-needle | Retire after Open WebUI (D0) and n8n use llama-swap | Done 2026-10-25 | [workflows](workflows.md) | Phase 3 |
| D8 | Review notifications | ntfy push; reviewer named per document type | Open | [Plutus](plutus.md) | Phase 3 |
| D12 | Intake mailbox | Dedicated Google account with plus addresses; Cloudflare routing optional | Open | [intake](intake.md) | Phase 4 |
| D13 | Calendar server | Radicale | Decided 2026-10-25: Radicale as its own service, git hook + timed push to Forgejo, rights per user; test both phones first | [Janus](janus.md) | Phase 5 |
| D14 | Vault dates in the calendar | Generic title + Paperless link only | Open | [Janus](janus.md) | Phase 5 |
| D15 | Recipe app | Mealie | Open | [Ceres](ceres.md) | Phase 6 |
| D16 | Instagram access | Caption-only first; throwaway-account cookies if that falls short | Open | [Ceres](ceres.md) | Phase 6 |
| D17 | Shell steps for workflows | `webhook` + bash media worker on helarctos | Open | [workflows](workflows.md#shell-steps) | Phase 6 |
| D22 | Public recipe sharing | Not yet; export instead | Open | [Ceres](ceres.md) | Phase 6 |
| D7 | OCR re-check interval | 6 months, then tune from flag rates | Open | [Plutus](plutus.md) | Phase 7 |
| D20 | Single sign-on | Later, after the apps exist; Pocket ID as candidate | Open | [shared-services](shared-services.md) | Later |
