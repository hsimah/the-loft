# Coding agents

Live: Forgejo ([Kennl](../services/kennl.md)) label events trigger an n8n workflow, which runs Claude Code through user `rodnik` on space-needle. Local models do no coding; household work has the GPU (D18). Background: [#155](https://github.com/hsimah/the-loft/issues/155).

## Runner

- **Entry:** n8n SSHes in as `rodnik` with the key in [n8n_rodnik_ed25519.pub](../../services/sputnik/claude-headless/n8n_rodnik_ed25519.pub). Its [forced command](../../services/sputnik/claude-headless/claude-headless-ssh-command) accepts only `implement`, `rework` and `review` for a repository and a `claude/*` branch.
- **Git on the host:** the forced command clones, checks out, commits and pushes as `rodnik`. Claude edits files only inside the sandbox. `review` pushes nothing.
- **Sandbox:** rootless Podman ([Containerfile](../../services/sputnik/claude-headless/Containerfile.claude-headless)), reaching only the Anthropic API, through a tinyproxy allowlist ([hosts](../../services/sputnik/claude-headless/tinyproxy-allowed-hosts)).
- **Models:** Sonnet for `implement` and `rework`, Opus for `review`. Each run is capped at 30 minutes.
- **Provisioning:** [provision-rodnik.sh](../../services/sputnik/claude-headless/provision-rodnik.sh), run as root on space-needle.

## Repositories

Every Forgejo repository is agent-ready; nothing runs until someone puts an agent label on an issue.

- **Trigger:** one Forgejo system webhook (Site Administration → Webhooks) sends issue label events from every repository to n8n.
- **Labels and access:** [kennl-agent-ready.sh](../../control-plane/kennl-agent-ready.sh) copies the label set from `hsimah-services/listory` and gives `rodnik` write access. It is idempotent: run `--dry-run --all`, then `--all`, after adding repositories.
- **New repositories:** create them from the `hsimah/template` template repository with **Labels** ticked. Templates do not copy collaborators, so add `rodnik` or re-run the script.

## Rules shared with household work

- Household content (wiki, vault, calendar, mail) goes to local models only, never Claude. Claude Pro is for code.
- Agents get no fleet access, and none to the vault.
