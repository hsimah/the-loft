# Names (D1)

Follows the [naming rules](../../CLAUDE.md#names): a primary application keeps the service name; helpers take it as a prefix.

## Decided

| Service | Name | Containers |
|---|---|---|
| Household wiki ([Mercurius](mercurius.md)) | `mercurius`: Roman god of commerce, eloquence and communication; the planet Mercury | `mercurius` (SilverBullet), `mercurius-git` |
| Vault ([Plutus](plutus.md)) | `plutus`: god of wealth and buried ore and gems. Sounds like Pluto but is unrelated | `plutus` (Paperless-ngx), `plutus-db`, `plutus-redis`, `plutus-tika`, `plutus-gotenberg`, `plutus-gpt`, `plutus-fetch` |

**No name needed**: ntfy (Houstn `notify` profile), the media worker (Sputnik profile, `sputnik-worker`), the reports (n8n workflows in Sputnik).

## Open

Calendar and recipes could be profiles inside Mercurius (communication fits the calendar and its reports), or names of their own.

Calendar and reports:

- `walkies` — the dog's daily routine.
- `capcom` — Mission Control's voice to the crew; the morning report.
- `tminus` — the countdown to every date.

Recipes:

- `kibbl` — dog food.
- `chowr` — chow, and the chow chow, a spitz breed.
- `treatz` — what every pomsky works for.

Intake addresses (`<name>@hsimah.com`, if Cloudflare routing is used):

- `fetch` — the dog fetches the post.
- `postie` — every dog's nemesis.
