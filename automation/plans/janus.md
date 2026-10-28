# Janus: calendar, reminders and reports

A local calendar that gathers dates from every source and turns them into timely reports:

> It's now October. You have a work trip in 12 days, and later this month the council rates are due for the Carlisle apartment. Nothing on the agenda today, but this week you wanted to repair the shelf in the sun room.

Janus is its own service, not part of [Mercurius](mercurius.md): phones sync with it directly, and it has its own storage and backup.

## Stack

| Piece | Proposed | Notes |
|---|---|---|
| Server | [Radicale](https://radicale.org/v3.html) (D13), container `janus` | CalDAV/CardDAV. One `.ics` file per event or task on disk. Multiple users with per-calendar rights. Not in Radicale's own tested-client list for iOS, though widely used with it: test both phones first. [Xandikos](https://www.xandikos.org/clients/) (git-native, iOS tested, single user) is the fallback |
| History | Radicale's storage hook commits every change to a local git repo, recording the user. `janus-git` pushes it to a private Forgejo repo on a timer | Never push from the hook: every phone save would wait on the network. Forgejo is read-only history; never edit files there |
| Phones | CalDAV over HTTPS through Caddy at a `*.loft.hsimah.com` name; Caddy's Let's Encrypt certificate satisfies iOS | iOS: Settings → Calendar → Accounts → Other → CalDAV. Android: DAVx5. Away from home, phones sync on return, or anywhere with Tailscale (D9) |
| Automation | n8n, container to container on `loft-proxy` | HTTP Request nodes speaking CalDAV, iCalendar built in a Code node; community nodes are disabled |
| Chat | A CalDAV MCP server, such as [caldav-mcp](https://glama.ai/mcp/servers/gelse/caldav-mcp) (unreviewed) | Open WebUI tools ("what's due this month?"); n8n's AI agent nodes can use it too |
| Reports | n8n, new workflows | |
| Push | ntfy ([shared services](shared-services.md)) | |

All writes go through CalDAV so phones see them on their next sync.

## Calendars and users

- `household`: accepted events, including recurring ones (council rates quarterly, registrations yearly).
- `proposed`: everything a model extracted. Accept by moving the event to `household` in any client; this is the review queue.
- `tasks`: VTODOs like the shelf repair, which iOS Reminders can edit.

| User | Reads | Writes |
|---|---|---|
| Each of you | All | All |
| n8n and the MCP server | All | `proposed`, `tasks` |
| Paperless date exporter | None | `household` |

Radicale's rights file enforces this, so the review queue doesn't depend on a prompt behaving.

## Sources

| Source | Path |
|---|---|
| Work and personal Google Calendar | Read by an n8n Google credential with read-only scopes ([Sputnik](../../docs/services/sputnik.md#google-oauth)); merged into reports, not copied |
| Filed emails | `+cal` [intake](intake.md) → model extracts date and title → `proposed` |
| Paper invoices, vaccination and ID expiry | [Paperless](documents.md) custom fields (due, expiry) → exporter → `household`, with reminders before the date |
| Manual | Any CalDAV client, or a note in the wiki `inbox/` |

**Vault dates leak by default** (D14): an event title is visible to every calendar client and to n8n. The exporter runs in the vault group and writes only a generic title ("Council rates: Carlisle") plus a link to the Paperless document. Amounts and account numbers stay in the vault.

## Reports

- **Morning** (daily, after the overnight GPU window), **weekly** (Sunday) and **monthly look-ahead** (the 1st), plus **on demand** from a Homepage link to an n8n webhook.
- Facts are assembled in code: date arithmetic, "in 12 days", what is due this week. The model only phrases them, so it cannot invent a date.
- Output: a report page, a short ntfy push, and optionally spoken through [Howlr](../../docs/services/howlr.md) with a local TTS voice. That last one is an idea, not a commitment.

## Open questions

- Which reports do you want, at what time, and to whom (one shared or one each)?
- Should reminders be calendar alarms on the phone, ntfy pushes, or both?
