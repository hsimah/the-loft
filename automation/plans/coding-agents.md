# Coding agents

In progress, tracked in [#155](https://github.com/hsimah/the-loft/issues/155): Forgejo ([Kennl](../../docs/services/kennl.md)) on space-needle, runner and llama-swap on helarctos, the listory pipeline being ported ([#152](https://github.com/hsimah/the-loft/issues/152)), model choice in [#149](https://github.com/hsimah/the-loft/issues/149), and personas and evals in [#156](https://github.com/hsimah/the-loft/issues/156). The issues are canonical; this page records only what the household work shares with it.

## Shared with household work

| Shared piece | Effect |
|---|---|
| llama-swap and GTT | #149's model choice decides whether household models stay resident (D18, [models](models.md#sharing-the-gpu)) |
| Overnight window | Coding is batch work overnight; household batch needs a slot too |
| Forgejo | Hosts the wiki repo and its agent PRs |
| Agent harness (`agent-run.sh`, #152) | Reused for the [LLM wiki agent](mercurius.md#llm-wiki-agent) |
| Kennl egress policy | Wiki agent jobs run under the same sandbox |
| Forgejo backup | Still open; the wiki repo adds to the reason ([backups](backups.md)) |

## Rules shared with household work

- Household content (wiki, vault, calendar, mail) goes to local models only, never Claude. Claude Pro is for code.
- Agents get no fleet access, and none to the vault.
