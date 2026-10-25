# Mercurius: household wiki

A shared, easy-to-edit space for plans, trips, places, projects, lists and notes. Plain markdown files with full history, editable by both of you from phone and laptop. Nothing from [Plutus](plutus.md) goes in here. Priority one in the [roadmap](roadmap.md#phase-1--mercurius).

## Stack

| Piece | Proposed | Notes |
|---|---|---|
| Editor | [SilverBullet](https://silverbullet.md) (D2), container `mercurius` | Web app and offline PWA over a folder of markdown files; wiki links, backlinks, queries. 2.11.x as of October 2026 (unverified) |
| Files | `/mammoth/mercurius/space` on space-needle | Plain `.md` plus attachments; the editor owns nothing else |
| History | `mercurius-git` sidecar commits the space every few minutes and pushes to a private repo on [Forgejo](../../docs/services/kennl.md) (D3) | Forgejo is history, not backup; see [backups](backups.md) |
| Desktop alternative | Obsidian on a clone of the same repo | Optional; same files |
| Access | Caddy LAN route on `*.loft.hsimah.com`; off-LAN through Tailscale (D9) | Never on the tunnel |
| AI upkeep | LLM wiki agent, later ([phase 7](roadmap.md#phase-7--ai-upkeep)) | See below |

SilverBullet authenticates a single user (`SB_USER`); verify on the pinned version. Either share one household login, or turn its auth off and put two users on Caddy `basic_auth` (LAN/Tailscale only).

## Layout

Suggested top level, refined once in use:

- `inbox/` — drop zone. Intake, the phone and agents write here; the agent files it.
- `home/`, `trips/`, `places/`, `projects/`, `lists/`, `people/` (non-sensitive only).
- `meta/conventions.md` — how pages are named and linked. The agent reads it first.

Dated items (the shelf repair, a trip) go in the [calendar](calendar.md); the wiki page holds the notes and links to the event.

## LLM wiki agent

The "LLM wiki" pattern ([example](https://github.com/enduserlab/llm-wiki)), pointed at the local models: turn dropped-in notes, links and emails into tidy pages with summaries and links between them.

- Runs overnight through the [#152](https://github.com/hsimah/the-loft/issues/152) harness (`agent-run.sh`, Claude Code against llama-swap), as a Forgejo job on the wiki repo. Same sandbox and egress rules as coding jobs.
- Works on a branch and opens a PR: AI suggests, you approve. Live edits land on `main` through the sidecar; the agent mostly adds pages, so conflicts should be rare.
- Local models only. Household content never goes to Claude ([coding-agents](coding-agents.md#rules-shared-with-household-work)).

## Open questions

- D2: is a web/PWA editor what you'd actually use on the phone, or Obsidian?
- D19: once the wiki is live, do these planning pages move into it? Recommendation: no, they describe fleet config and belong next to it.
