# Initial runner prototype and Fjord workload retirement

**Role update (2026-09-26):** Agent development is assigned to the owner's
**Ladygrey, Surface Pro 3 (Core i5, 8 GB RAM)**. See the authoritative
[Ladygrey plan](../../plans/ladygrey-development-runner.md). Fjord remains
Snoot/Houstn monitoring-only pending a new purpose; no agent scheduler, checkouts
or credentials should be provisioned there. Space-needle is not the worker.

The retirement commands below still apply to Fjord. Subsequent sections document
the existing, unenabled Docker-wrapped agent prototype. Ladygrey will run agents
natively on Debian and use Docker for application environments. The native adapter
and host configuration are now prepared; use the [Ladygrey runbook](ladygrey-setup.md)
for onboarding. No VM is planned. Its `hosts/fjord/dev-runner/`, `/srv/fjord-dev`, image and container
names are legacy placeholders to migrate during Surface onboarding. Do not run
those setup sections on Fjord. No remote configuration has been applied.

## Retire old Fjord workloads

On **Fjord only**, from `/srv/the-loft` after installing these repository changes:

```bash
sudo docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
sudo docker compose -f services/howlr/docker-compose.yml --profile client --profile server down
sudo docker compose -f services/pawst/docker-compose.yml \
  -f hosts/fjord/overrides/pawst/docker-compose.override.yml down
sudo docker compose -f services/mushr/docker-compose.yml \
  -f hosts/fjord/overrides/mushr/docker-compose.override.yml down
sudo bash setup.sh
loft-ctl start snoot houstn
loft-ctl health
sudo docker ps --format 'table {{.Names}}\t{{.Status}}'
```

These commands preserve application data; do not add `--volumes`. Removing a
manifest entry alone does not stop containers. If a Compose command fails due to
missing historical environment settings, inspect and resolve the error. Compare
the inventory for legacy containers outside these projects and retire those exact
containers too. Check `systemctl status snapclient` for a native audio service;
if present on Fjord, disable it with `sudo systemctl disable --now snapclient`.

The new [Houstn override](../../hosts/fjord/overrides/houstn/docker-compose.override.yml)
selects only Glances regardless of stale profile settings. If hub containers
(Beszel server, Homepage or Uptime Kuma) were previously started here, retire
those identified containers too. Snoot's Beszel **agent** stays running. Keep old
`/opt/pawst` and audio data until a separate cleanup decision.

## Checkouts and read-only queue inspection

Run the scripts as `adminhabl`, not root. Install Python 3, Git and GitHub CLI from
supported packages. Authenticate that account for `hsimah/clog` and
`hsimah-services/toroid`. For ongoing automation, use a repository-scoped GitHub
identity with source, issue-label and PR permissions.

```bash
sudo install -d -o adminhabl -g adminhabl -m 0700 /srv/fjord-dev
sudo install -d -o adminhabl -g adminhabl -m 0700 /etc/loft/dev-runner
sudo install -o adminhabl -g adminhabl -m 0600 \
  hosts/fjord/dev-runner/config.example.json /etc/loft/dev-runner/config.json
gh auth login
gh auth setup-git
python3 control-plane/dev-runner.py --config /etc/loft/dev-runner/config.json init-repos
python3 control-plane/dev-runner.py --config /etc/loft/dev-runner/config.json poll
```

The checkouts are `/srv/fjord-dev/projects/hsimah--clog` and
`/srv/fjord-dev/projects/hsimah-services--toroid`. Existing directories are left
untouched. Jobs use independent clones of the remote default branch rather than
resetting these manual checkouts. `poll` is read-only and needs no Claude login.

Create these labels in each repository: `agent:ready`, `agent:claude`,
`agent:running`, `agent:review`, `agent:blocked`, `agent:cancel`. Queue an issue
with **both ready and claude**. Running/review/blocked/cancel issues, PRs and
issues also labeled `agent:codex` are excluded. The author allowlist defaults to
`hsimah`. This starter trusts repository collaborators who can apply labels; it
does not independently verify which collaborator applied the label.

## Worker and authentication

Use a host with enough physical RAM; the example requires about 3.5 GiB reported
RAM to allow for system reservations on a 4 GB machine. It intentionally refuses
execution on the 1 GB Pi. Ladygrey has 8 GB; this check alone does not
validate combined agent/application capacity. `uname -m`, `free -h`, `df -h / /srv` and
`sudo docker stats --no-stream` establish the baseline. A worker also needs Docker
access for the runner account. Start with one job at a time.

Ladygrey will poll GitHub directly and run native agent sessions.
Adapting the prototype to native execution and account permissions is still required. Fjord has no
scheduling or checkout role. Do not enable the same queue
on two machines: the lock and journal are local.

Build the [starter image](../../services/dev-runner/Dockerfile) on the worker's
architecture, and record the resulting image ID/digest in configuration:

```bash
sudo docker build -t fjord-dev-worker:2026-09-26 services/dev-runner
sudo docker run --rm fjord-dev-worker:2026-09-26 claude --version
```

The image includes Claude, Node/npm/pnpm, PHP/Composer and Rust based on the two
applications' toolchains. CLI build arguments are versioned; the base images use
moving release tags, so a recorded built digest is needed for reproducibility.
It has not been built or tested on the Surface. There are no WordPress/MySQL/Redis or
browser sidecars yet. Repository scripts that call Docker must be replaced with
direct in-container commands for supported initial tasks.

Keep Claude authentication **on the worker**, outside Git. For an existing
Pro/Max subscription, ordinary interactive Claude login is suitable for a manual
session. For this disposable-container runner, use `claude setup-token` on your
authenticated machine and place the resulting token in the worker's mode-600
`/etc/loft/dev-runner/provider.env` as `CLAUDE_CODE_OAUTH_TOKEN=...`.
Alternatively, put an Anthropic Console API key there as `ANTHROPIC_API_KEY=...`;
that uses API billing. Choose exactly one. Never paste credentials into an issue
or commit them. GitHub Secrets are needed only if GitHub Actions runs the worker.
See [authentication](https://code.claude.com/docs/en/authentication) and
[CLI reference](https://code.claude.com/docs/en/cli-reference).

The worker receives only the provider environment file, not GitHub write
credentials, host SSH keys or the operator's home. Code executing in that
container can read its provider credential. Claude uses an ephemeral home,
explicit tool permissions, disabled hooks and an empty MCP configuration.
Its Git metadata is mounted read-only. The host handles commits and publication.
See [Claude headless execution](https://code.claude.com/docs/en/headless).

## Configure and run a first issue

Copy [prompt.example.md](../../services/dev-runner/prompt.example.md) to
`/etc/loft/dev-runner/prompt.md` and adapt it into the standard prompt. The example
is a starting draft, not an assumption that the final prompt has been agreed.

Set the commit email, image and each project's `prepare` and `checks` arrays in
the config. Entries are argv lists, for example
`["composer", "--working-dir=server", "install", "--no-interaction"]`.
Checks are deliberately empty initially: verify actual commands against clean
clones before enabling jobs. Clog has PHP unit tests and frontend lint/build/Relay
checks; Toroid has Elephentity and frontend checks. Private packages, schema
generation and x86-64 toolchain compatibility still need onboarding. A whitespace check
alone is not adequate application validation.

Preparation, Claude and validation each run in disposable containers sharing the
job checkout. Dependencies installed into that checkout persist; ephemeral homes
and background processes do not. No Docker socket is mounted. Containers have
CPU/memory/PID limits, non-root identity and read-only roots with explicit writable
mounts. They use Docker's default bridge, which **does not isolate the LAN**.
Apply/test forwarded-traffic restrictions on the worker or choose an isolated
worker before unattended use; full networking/sidecar implementation remains
in the plan.

Set `enabled` and `prompt_approved` true only on the configured worker, then test
one small issue manually:

```bash
python3 control-plane/dev-runner.py --config /etc/loft/dev-runner/config.json run
python3 control-plane/dev-runner.py --config /etc/loft/dev-runner/config.json status
```

The runner claims one issue, starts Claude, checks its structured completion
report, runs configured validation and creates a draft PR on a unique branch.
Failed checks or incomplete results become blocked. No auto-merge or deployment
occurs. Snapshots, prompt, logs and checkout persist under
`/srv/fjord-dev/jobs/<job-id>/`. These are not automatically deleted.

After manual acceptance, install and uncomment
[cron.example](../../hosts/fjord/dev-runner/cron.example) as
`/etc/cron.d/loft-dev-runner`. It polls every five minutes and holds one lock for
the whole run. Configure rotation for `/srv/fjord-dev/cron.log` and a job retention
policy before ongoing use. Fleet setup does not install or enable cron.

## Recovery and initial limits

All commands use the same `--config` argument:

- `status`: display recorded job states. Recorded issues do not automatically rerun.
- `publish JOB_ID`: publish an unchanged validated commit, reconciling an existing
  PR first. Does not rerun Claude or recreate a closed PR.
- `recover JOB_ID`: after an interrupted runner exits, remove that exact labeled
  container, preserve work and mark blocked or publish-pending. Unfinished records
  prevent new execution until recovered or published.
- `requeue JOB_ID`: explicitly allow a new attempt of a blocked, uncommitted job.
  Remove `agent:cancel` separately if set.

`agent:cancel` prevents selection/publication but does not interrupt an active
model call yet. For immediate cancellation add the label and run
`sudo docker stop fjord-job-<job-id>`; recover the record if the host process was
also interrupted. The wall-clock limit covers worker preparation, Claude and
checks; host Git/GitHub calls have separate timeouts. A timed-out container is
explicitly removed, and execution failures are not automatically retried.

Tests use real local Git repositories with mocked GitHub/container calls. They
do not prove live authentication, Ladygrey workload capacity or network isolation. Distributed
dispatch, CI feedback loops, provider failover, automatic retention and web
sidecars remain later work.
