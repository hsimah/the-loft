# forgejo-agent

n8n workflows that run Claude Code on Forgejo issues and pull requests, driven by labels ([coding agents](../../../docs/automation/coding-agents.md)). Each one is a webhook from Forgejo, a gate, an SSH call to `rodnik`'s [forced command](../claude-headless/claude-headless-ssh-command) on space-needle, and label updates through the Forgejo API as `rodnik`.

| Workflow | Webhook path | Trigger | Runs | Then |
|---|---|---|---|---|
| [coding](forgejo-agent-coding.json) | `forgejo-issue-label` | `agent:ready` on an open issue | `implement` on `claude/issue-<n>` | Opens a PR labelled `agent:review` and links it on the issue; on failure, comments and labels the issue `agent:needs-human` |
| [review](forgejo-agent-review.json) | `forgejo-pull-request-label` | `agent:review` on an open PR from a `claude/` branch in the same repository | `review` (read-only) | Posts the review; `agent:human` and a review request to you on approve, `agent:changes` on changes, `agent:needs-human` on a bad verdict or after 3 rounds |
| [rework](forgejo-agent-rework.json) | `forgejo-pull-request-rework` | `agent:changes` on an open PR from a `claude/` branch in the same repository, with a Claude review or your comments to act on | `rework` on the PR's branch | Comments the pushed commit and relabels `agent:review`; otherwise `agent:needs-human` |

`agent:working` (issue and rework) and `agent:reviewing` (review) mark a run in progress, and a second event while one is on is ignored.

## Gates

- `agent:ready` counts only from `hsimah` on an issue `hsimah` wrote; the timeline is rechecked, so the payload alone cannot trigger a run.
- `agent:review` and `agent:changes` count from `hsimah` or `rodnik`, so the loop runs implement → review → rework → review without you until approve or the round limit.
- Issue text reaches Claude only from issues `hsimah` wrote; PR comments only from `hsimah`. Owner and runner logins and the API base URL are constants in each workflow's first Code node.

## Setup

1. Create the seven `agent:*` labels above at organisation level; a claim fails if its label is missing.
2. Credentials in n8n, before importing (the exports name them but hold no secrets):
   - `Forgejo webhook (inbound)`: Header Auth that the webhook triggers check. Its value goes in each Forgejo webhook's Authorization header.
   - `Forgejo credential (rodnik)`: Header Auth carrying `rodnik`'s Forgejo API token.
   - `SSH Private Key account`: `rodnik@space-needle` with the private half of [n8n_rodnik_ed25519.pub](../claude-headless/n8n_rodnik_ed25519.pub).
3. Import each file (⋯ → Import from File), reselect the credentials on the nodes, then publish.
4. In Forgejo, add a webhook per workflow pointing at its production URL (`https://n8n.loft.hsimah.com/webhook/<path>`), with the Authorization header from step 2, for the custom event **Issue Label** (coding) or **Pull Request Label** (review and rework). Forgejo refuses private addresses by default, so its `app.ini` `[webhook] ALLOWED_HOST_LIST` must admit n8n.
