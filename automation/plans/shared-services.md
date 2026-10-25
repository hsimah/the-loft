# Shared services

Pieces used by more than one use case. Build each once, in the first phase that needs it ([roadmap](roadmap.md)).

| Piece | Where | Used by | State |
|---|---|---|---|
| llama-swap ([models](models.md)) | helarctos, Sputnik `gpu` | Coding, chat, vault, wiki, calendar, recipes, n8n | Live: coding evaluation models, Open WebUI chat; household models not added |
| n8n ([workflows](workflows.md)) | space-needle, Sputnik `agent` | Intake, calendar, reports, recipes, wiki inbox | Live on CPU Ollama (briefing) |
| Media worker ([workflows](workflows.md#shell-steps)) | helarctos, Sputnik profile | Recipe reels, voice notes | Proposed |
| Intake mailbox ([intake](intake.md)) | Google account | Vault, wiki, calendar, recipes | Proposed |
| ntfy | space-needle, as a Houstn `notify` profile | Vault review flags, reminders, reports, intake rejects; Uptime Kuma can use it too | Proposed |
| Forgejo ([Kennl](../../docs/services/kennl.md)) | space-needle | Coding, wiki history, wiki agent PRs | Live |
| Agent harness ([#152](https://github.com/hsimah/the-loft/issues/152)) | helarctos runner | Coding, wiki agent | In progress |
| Off-site backups ([backups](backups.md)) | space-needle → Google Drive | Vault, wiki, calendar, recipes, n8n, Forgejo | Proposed; first slice of [#108](https://github.com/hsimah/the-loft/issues/108) |
| Tailscale (D9) | Phones, laptops, space-needle | Off-LAN access to every household app | Used for Viking management; not on phones |
| Mushr ([Caddy, DNS](../../docs/services/mushr.md)) | space-needle | Every UI | Live |
| OIDC single sign-on, e.g. Pocket ID (D20) | space-needle | Optional: one passkey login for Paperless, Mealie, Forgejo; also the only way to give [Hubbl](../../docs/services/hubbl.md) a second factor | Idea |

## Trust zones

| Zone | Contents | Rules |
|---|---|---|
| Open household | Mercurius (wiki), calendar, recipes, n8n, ntfy | LAN and Tailscale. May reach llama-swap and the internet as each app needs |
| Vault | Plutus: Paperless, helpers and `plutus-fetch` | Own network and encrypted volume. Egress only to llama-swap (fetcher: Gmail IMAP). Writes outward only through the calendar exporter |
| Compute | helarctos | Stateless for household work; no inbound path to space-needle data |

Today every space-needle bridge app shares `loft-proxy`. The vault should not join it: give Caddy a leg on a vault-only network instead ([#104](https://github.com/hsimah/the-loft/issues/104)).
