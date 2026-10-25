# Calendar, reminders and reports

A local calendar that gathers dates from every source and turns them into timely reports:

> It's now October. You have a work trip in 12 days, and later this month the council rates are due for the Carlisle apartment. Nothing on the agenda today, but this week you wanted to repair the shelf in the sun room.

## Stack

| Piece | Proposed | Notes |
|---|---|---|
| Server | [Radicale](https://radicale.org) (D13) | Small CalDAV/CardDAV server. One `.ics` file per item on disk, so backups and diffs are trivial. Baïkal is similar; Stalwart only if self-hosted mail ([#18](https://github.com/hsimah/the-loft/issues/18)) happens |
| Clients | iOS Calendar and Reminders natively; Android with DAVx5 | Off-LAN sync needs Tailscale (D9) |
| Reports | n8n, extending the [briefing workflow](../../services/sputnik/workflows/briefing.md) | |
| Push | ntfy ([shared services](shared-services.md)) | |

Calendars in Radicale:

- `household`: accepted events, including recurring ones (council rates quarterly, registrations yearly).
- `proposed`: everything a model extracted. Accept by moving the event to `household` in any client; this is the review queue.
- `tasks`: VTODOs like the shelf repair, which iOS Reminders can edit.

## Sources

| Source | Path |
|---|---|
| Work and personal Google Calendar | Read by n8n's existing read-only credential; merged into reports, not copied |
| Filed emails | `+cal` [intake](intake.md) → model extracts date and title → `proposed` |
| Paper invoices, vaccination and ID expiry | [Vault](vault.md) custom fields (due, expiry) → exporter → `household`, with reminders before the date |
| Manual | Any CalDAV client, or a note in the wiki `inbox/` |

**Vault dates leak by default** (D14): an event title is visible to every calendar client and to n8n. The exporter runs in the vault group and writes only a generic title ("Council rates: Carlisle") plus a link to the Paperless document. Amounts and account numbers stay in the vault.

## Reports

- **Morning** (daily, after the overnight GPU window), **weekly** (Sunday) and **monthly look-ahead** (the 1st), plus **on demand** from a Homepage link to an n8n webhook.
- Facts are assembled in code: date arithmetic, "in 12 days", what is due this week. The model only phrases them, so it cannot invent a date.
- Output: the briefing page, a short ntfy push, and optionally spoken through [Howlr](../../docs/services/howlr.md) with a local TTS voice. That last one is an idea, not a commitment.

## Open questions

- Which reports do you want, at what time, and to whom (one shared or one each)?
- Should reminders be calendar alarms on the phone, ntfy pushes, or both?
