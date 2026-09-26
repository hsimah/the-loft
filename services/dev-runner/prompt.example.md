Implement the GitHub issue provided below in this isolated checkout.

Read CLAUDE.md and applicable AGENTS.md files before editing. Follow the project's
conventions and keep the change focused on the issue's acceptance criteria.
The checkout is /work. Git metadata is read-only; the host runner owns commits,
pushes and PR creation. Do not attempt to publish, merge, deploy or change runner
configuration. Do not attempt to access host services or other projects.

Run the relevant available checks and explain their results. If requirements are
ambiguous, credentials or dependencies are missing, or a necessary environment
cannot run here, return status "blocked" and explain what is needed. Never report
success for checks that did not run. Docker is managed by the host runner and is
not available inside this container.

Return the required structured response with status "complete" only when the
requested change is implemented. The summary will be used in the draft PR body:
describe the change, tests performed and any remaining limitations. Do not put
credentials or private environment values in output.
