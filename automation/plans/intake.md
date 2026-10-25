# Email intake

Curated mail only: you forward what should be filed; nothing arrives just because someone sent it. One intake mailbox feeds the [vault](vault.md), [open brain](open-brain.md), [calendar](calendar.md) and [recipes](recipes.md).

## Mailbox (D12)

A **dedicated Google account** used only for intake, not your main Gmail. The main account's n8n credential stays read-only ([Sputnik](../../docs/services/sputnik.md#google-oauth)), and the intake account holds nothing else worth stealing.

Addresses, one per destination:

| Address | Destination |
|---|---|
| `…+vault@gmail.com` | Vault |
| `…+wiki@gmail.com` | Wiki `inbox/` |
| `…+cal@gmail.com` | Proposed calendar events |
| `…+recipe@gmail.com` | Recipes |

Optional: [Cloudflare Email Routing](https://developers.cloudflare.com/email-routing/) on `hsimah.com` gives nicer addresses (`vault@hsimah.com`, …) forwarding to the intake account. It needs hsimah.com's MX records, so check nothing already receives mail there. MX could later move to a self-hosted server ([#18](https://github.com/hsimah/the-loft/issues/18)) without changing the addresses.

## Getting mail there

- **By hand**: forward from any mail app.
- **By rule**: a Gmail filter in the main account auto-forwards known senders (council rates, utilities, the vet) to the right address. Gmail verifies each forwarding address once.

## Acceptance

A message is processed only when both hold; anything else is moved to `rejected`, logged, and never shown to a model:

1. `From` is on an allowlist (your addresses).
2. The intake account's `Authentication-Results` header shows DKIM pass for that sender's domain.

Forwarded content is still untrusted text. Models that read it have no tools, and their output lands in a review queue (Paperless inbox, wiki PR, proposed calendar, Mealie draft).

## Consumers

Filters in the intake account sort mail into one label per address. Each consumer reads only its label over IMAP and moves processed mail to `done`. Auth: an app password, which personal accounts with 2-step verification still offer (secondhand sources; verify), otherwise IMAP XOAUTH2.

### n8n router

Reads `wiki`, `cal` and `recipe` ([workflows](workflows.md)): IMAP trigger, sender check, then route.

### Vault fetcher

Reads `vault` only. A small container in the vault group with egress only to `imap.gmail.com:993`. It writes each `.eml` into Paperless's consume folder, so Paperless itself stays offline and n8n never sees vault mail. Shares the sender check with n8n as a bash helper.
