# Mercurius: household wiki

SilverBullet in multi-space mode, configured in the repo and not yet deployed: [service page](../../docs/services/mercurius.md). One account each, a `household` space, and SilverBullet's own git revisions synced to a private Forgejo repo (D2, D3). Nothing from [Plutus](plutus.md) goes in here. This page holds the remaining work; see the [roadmap](roadmap.md#phase-1--mercurius).

## Remaining

- Off-LAN access through Tailscale (D9).
- Encrypted off-site backup of `/mammoth/mercurius` ([backups](backups.md)).
- Obsidian on a clone of the Forgejo repo, if wanted. Edits made that way reach SilverBullet through its git sync, which fetches and merges; it is built as a backup, not for collaboration, so expect the odd conflict to resolve in the wiki.

## Layout

Suggested top level, refined once in use:

- `inbox/` — drop zone. Intake, the phone and agents write here; the agent files it.
- `home/`, `trips/`, `places/`, `projects/`, `lists/`, `people/` (non-sensitive only).
- `meta/conventions.md` — how pages are named and linked. The agent reads it first.

Dated items (the shelf repair, a trip) go in [Janus](janus.md); the wiki page holds the notes and links to the event.

## LLM wiki agent

The "LLM wiki" pattern ([example](https://github.com/enduserlab/llm-wiki)), pointed at the local models: turn dropped-in notes, links and emails into tidy pages with summaries and links between them.

- Runs overnight through the [#152](https://github.com/hsimah/the-loft/issues/152) harness (`agent-run.sh`, Claude Code against llama-swap), as a Forgejo job on the wiki repo. Same sandbox and egress rules as coding jobs.
- Works on a branch and opens a PR: AI suggests, you approve. A merged PR reaches the wiki through SilverBullet's git sync; the agent mostly adds pages, so conflicts should be rare.
- SilverBullet records changes it didn't make itself as **External**, so agent edits stay distinguishable in page history.
- Local models only. Household content never goes to Claude ([coding-agents](coding-agents.md#rules-shared-with-household-work)).

## Open questions

- D19: once the wiki is live, do these planning pages move into it? Recommendation: no, they describe fleet config and belong next to it.
