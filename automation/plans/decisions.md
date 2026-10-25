# Decisions

Register of open choices. When one is made, set Status to the decision and date, update the topic page, and drop the losing options from it.

| ID | Decision | Recommendation | Status | Page | Needed by |
|---|---|---|---|---|---|
| D0 | Chat portal | Open WebUI on llama-swap now, ahead of phase 3 | Decided 2026-10-25 | [workflows](workflows.md#chat) | Now |
| D1 | Service names | Pick from the proposals | Open | [names](names.md) | Phase 1 |
| D2 | Wiki editor | SilverBullet; Obsidian optional on the same repo | Open | [open-brain](open-brain.md) | Phase 1 |
| D3 | Wiki history | Sidecar autocommit to a private Forgejo repo | Open | [open-brain](open-brain.md) | Phase 1 |
| D9 | Off-LAN access | Tailscale on phones and laptops; nothing on the tunnel | Open | [shared-services](shared-services.md) | Phase 1 |
| D10 | Off-site backup tool | restic through rclone to Google Drive | Open | [backups](backups.md) | Phase 1 |
| D11 | Backup key custody | Password manager + printed sheet in the safe; both of you can restore | Open | [backups](backups.md) | Phase 1 |
| D19 | Planning pages after the wiki is live | Stay in this repo | Open | [open-brain](open-brain.md) | Phase 1 |
| D4 | Vault areas | Shared to start; Paperless permissions can split later | Open | [vault](vault.md) | Phase 2 |
| D5 | Vault encryption at rest | LUKS volume unlocked by hand after each boot. A keyfile on the root disk only protects a stolen data disk | Open | [vault](vault.md) | Phase 2 |
| D6 | First records in | Your call: tax and financial, medical, or IDs | Open | [vault](vault.md) | Phase 2 |
| D18 | GPU residency and night split | Keep the household set resident; prefer a coder that fits beside it; household batch 01:00–02:30 | Open; depends on [#149](https://github.com/hsimah/the-loft/issues/149) | [models](models.md#sharing-the-gpu) | Phase 3 |
| D21 | Ollama on space-needle | Retire after Open WebUI (D0) and n8n use llama-swap | Open | [workflows](workflows.md) | Phase 3 |
| D8 | Review notifications | ntfy push; reviewer named per document type | Open | [vault](vault.md) | Phase 3 |
| D12 | Intake mailbox | Dedicated Google account with plus addresses; Cloudflare routing optional | Open | [intake](intake.md) | Phase 4 |
| D13 | Calendar server | Radicale | Open | [calendar](calendar.md) | Phase 5 |
| D14 | Vault dates in the calendar | Generic title + Paperless link only | Open | [calendar](calendar.md) | Phase 5 |
| D15 | Recipe app | Mealie | Open | [recipes](recipes.md) | Phase 6 |
| D16 | Instagram access | Caption-only first; throwaway-account cookies if that falls short | Open | [recipes](recipes.md) | Phase 6 |
| D17 | Shell steps for workflows | `webhook` + bash media worker on helarctos | Open | [workflows](workflows.md#shell-steps) | Phase 6 |
| D22 | Public recipe sharing | Not yet; export instead | Open | [recipes](recipes.md) | Phase 6 |
| D7 | OCR re-check interval | 6 months, then tune from flag rates | Open | [vault](vault.md) | Phase 7 |
| D20 | Single sign-on | Later, after the apps exist; Pocket ID as candidate | Open | [shared-services](shared-services.md) | Later |
