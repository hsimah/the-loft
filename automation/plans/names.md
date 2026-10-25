# Names (D1)

Decided 2026-10-25. Follows the [naming rules](../../CLAUDE.md#names): a primary application keeps the service name; helpers take it as a prefix. Each is a Roman god that is also, or sounds like, a body in the solar system.

| Service | Name | Containers |
|---|---|---|
| Household wiki ([Mercurius](mercurius.md)) | `mercurius`: god of commerce, eloquence and communication; the planet Mercury | `mercurius` (SilverBullet), `mercurius-git` |
| Vault ([Plutus](plutus.md)) | `plutus`: god of wealth and buried ore and gems. Sounds like Pluto but is unrelated | `plutus` (Paperless-ngx), `plutus-db`, `plutus-redis`, `plutus-tika`, `plutus-gotenberg`, `plutus-gpt`, `plutus-fetch` |
| Calendar ([Janus](janus.md)) | `janus`: god of beginnings and doorways, who gives January its name; a moon of Saturn | `janus` (Radicale), `janus-git` |
| Recipes ([Ceres](ceres.md)) | `ceres`: goddess of grain and harvest; a dwarf planet | `ceres` (Mealie), helpers for the reel pipeline as needed |

**No name needed**: ntfy (Houstn `notify` profile), the media worker (Sputnik profile, `sputnik-worker`), the reports (n8n workflows in Sputnik).

Intake addresses, if Cloudflare routing is used ([intake](intake.md)): open.
