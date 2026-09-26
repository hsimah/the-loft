#!/usr/bin/env python3
"""Single-host GitHub issue runner. Poll is read-only; run requires explicit enablement."""
import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time
import uuid


class RunnerError(RuntimeError):
    pass


def command(args, cwd=None, timeout=120, stdin=None):
    result = subprocess.run(args, cwd=cwd, input=stdin, text=True,
                            capture_output=True, timeout=timeout)
    if result.returncode:
        # Command arguments may contain issue text; don't echo them on error.
        raise RunnerError(f'{args[0]} exited {result.returncode}: {result.stderr[-2000:]}')
    return result.stdout.strip()


def gh(*args):
    return command(['gh', *args])


def git(repo, *args):
    return command(['git', '-c', 'core.hooksPath=/dev/null', '-C', str(repo), *args])


def write_json(path, value):
    temp = path.with_suffix('.tmp')
    with temp.open('w') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temp, path)
    fd = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def eligible(issue, project):
    labels = {label['name'] for label in issue['labels']}
    return (issue['state'] == 'open' and 'pull_request' not in issue
            and issue['user']['login'] in project['authors']
            and {'agent:ready', 'agent:claude'} <= labels
            and not labels.intersection({'agent:codex', 'agent:running',
                                         'agent:review', 'agent:blocked', 'agent:cancel'}))


def load_config(path):
    cfg = json.loads(path.read_text())
    cfg['root'] = str(Path(cfg['root']).expanduser().resolve())
    for project in cfg['projects']:
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', project['repo']):
            raise RunnerError('Invalid GitHub owner/repo')
        if not project.get('authors'):
            raise RunnerError('Each project requires an author allowlist')
    if len({p['repo'] for p in cfg['projects']}) != len(cfg['projects']):
        raise RunnerError('Duplicate project registration')
    return cfg


class Runner:
    def __init__(self, cfg):
        self.cfg = cfg
        self.root = Path(cfg['root'])
        self.jobs = self.root / 'jobs'

    @contextlib.contextmanager
    def lock(self):
        self.root.mkdir(parents=True, exist_ok=True)
        with (self.root / 'runner.lock').open('a') as handle:
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RunnerError('Another runner invocation is active')
            yield

    def records(self):
        return [json.loads(p.read_text()) for p in sorted(self.jobs.glob('*/job.json'))]

    def save(self, job, **values):
        job.update(values, updated_at=time.time())
        write_json(self.jobs / job['id'] / 'job.json', job)

    def issue(self, repo, number):
        return json.loads(gh('api', f'repos/{repo}/issues/{number}'))

    def candidates(self):
        recorded = {(r['repo'], r['issue']) for r in self.records() if r['state'] != 'requeued'}
        candidates = []
        for project in self.cfg['projects']:
            pages = json.loads(gh('api', '--paginate', '--slurp',
                f"repos/{project['repo']}/issues?state=open&labels=agent%3Aready,agent%3Aclaude&per_page=100"))
            for issue in (item for page in pages for item in page):
                if eligible(issue, project) and (project['repo'], issue['number']) not in recorded:
                    candidates.append((project, issue))
        return sorted(candidates, key=lambda pair: pair[1]['created_at'])

    def checkout_path(self, project):
        return self.root / 'projects' / project['repo'].replace('/', '--')

    def init_repos(self):
        for project in self.cfg['projects']:
            target = self.checkout_path(project)
            if target.exists():
                print(f'Already exists, left unchanged: {target}')
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            gh('repo', 'clone', project['repo'], str(target), '--', '--no-recurse-submodules')
            print(f'Cloned {project["repo"]}: {target}')

    def labels(self, job, state):
        remove = ','.join(f'agent:{s}' for s in ('ready', 'running', 'review', 'blocked') if s != state)
        gh('issue', 'edit', str(job['issue']), '--repo', job['repo'],
           '--remove-label', remove,
           '--add-label', f'agent:{state}')

    def preflight(self, project):
        if os.geteuid() == 0:
            raise RunnerError('Run as the dedicated operator account, not root')
        if not self.cfg.get('enabled') or not self.cfg.get('prompt_approved'):
            raise RunnerError('Set enabled and prompt_approved only after manual onboarding')
        prompt = Path(self.cfg['prompt_file']).read_text().strip()
        if not prompt:
            raise RunnerError('Prompt is empty')
        if not project.get('checks'):
            raise RunnerError('Configure at least one required validation command')
        native = self.cfg.get('execution') == 'native'
        if native and not Path(self.cfg.get('network_ready_file', '/etc/loft/dev-runner/network-reviewed')).is_file():
            raise RunnerError('Complete and record network review before native execution')
        if not native and not project.get('image'):
            raise RunnerError('Configure a tested worker image')
        for argv in project.get('prepare', []) + project['checks'] + project.get('teardown', []):
            if not isinstance(argv, list) or not argv or not all(isinstance(s, str) for s in argv):
                raise RunnerError('Prepare/check commands must be nonempty argv arrays')
        if shutil.disk_usage(self.root).free < self.cfg.get('min_free_disk_mb', 2048) * 1024**2:
            raise RunnerError('Insufficient free disk space')
        mem = dict(line.split(':', 1) for line in Path('/proc/meminfo').read_text().splitlines())
        if int(mem['MemTotal'].split()[0]) < self.cfg.get('min_host_memory_mb', 4096) * 1024:
            raise RunnerError('Host is below configured memory requirement; use a suitable worker host')
        if native:
            command(['claude', '--version'])
            gh('auth', 'status')
            return prompt
        env = Path(self.cfg['provider_env_file'])
        if env.stat().st_mode & 0o077:
            raise RunnerError('Provider environment file must have mode 600')
        keys = {line.split('=', 1)[0] for line in env.read_text().splitlines()
                if line.strip() and not line.startswith('#')}
        if not keys or not keys <= {'ANTHROPIC_API_KEY', 'CLAUDE_CODE_OAUTH_TOKEN'}:
            raise RunnerError('Provider file must contain only an API key or Claude OAuth token')
        if len(keys) != 1:
            raise RunnerError('Configure exactly one authentication method')
        command(['docker', 'image', 'inspect', project['image']])
        gh('auth', 'status')
        return prompt

    def container(self, job, project, argv, log, *, provider=False, stdin=None):
        """Run only in the job clone; Git metadata is read-only to the worker."""
        if self.cfg.get('execution') == 'native':
            return self.native(job, argv, log, stdin=stdin)
        directory = self.jobs / job['id']
        workspace = directory / 'work'
        name = f'fjord-job-{job["id"]}'
        uid, gid = os.getuid(), os.getgid()
        args = ['docker', 'run', '--rm', '-i', '--name', name,
                '--label', f'loft.dev-job={job["id"]}', '--init',
                '--user', f'{uid}:{gid}', '--cap-drop', 'ALL',
                '--security-opt', 'no-new-privileges', '--read-only',
                '--memory', self.cfg.get('container_memory', '2g'),
                '--cpus', str(self.cfg.get('container_cpus', 2)), '--pids-limit', '256',
                '--log-driver', 'none',
                '--tmpfs', f'/tmp:rw,size=256m,uid={uid},gid={gid}',
                '--tmpfs', f'/home/worker:rw,size=128m,uid={uid},gid={gid}',
                '--env', 'HOME=/home/worker', '--env', 'CI=true',
                '--env', 'DISABLE_AUTOUPDATER=1',
                '--mount', f'type=bind,src={workspace},dst=/work',
                '--mount', f'type=bind,src={workspace / ".git"},dst=/work/.git,readonly',
                '--workdir', '/work']
        if provider:
            args += ['--env-file', self.cfg['provider_env_file']]
        args += [project['image'], *argv]
        remaining = job['created_at'] + self.cfg.get('timeout_seconds', 3600) - time.time()
        if remaining <= 0:
            raise RunnerError('Job wall-clock limit reached')
        with (directory / log).open('w') as output, (directory / (log + '.stderr')).open('w') as errors:
            process = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=output,
                                       stderr=errors, text=True)
            try:
                process.communicate(stdin, timeout=remaining)
                if process.returncode:
                    raise RunnerError(f'Worker exited {process.returncode}; see {log}')
            finally:
                # Killing docker's client alone does not stop the worker container.
                subprocess.run(['docker', 'rm', '-f', name], capture_output=True, timeout=30)
                if process.poll() is None:
                    process.kill()
                    process.wait()

    def native(self, job, argv, log, *, stdin=None, cleanup=False):
        """Native child process group; the service cgroup provides final cleanup."""
        directory = self.jobs / job['id']
        env = dict(os.environ, CI='true', DISABLE_AUTOUPDATER='1',
                   COMPOSE_PROJECT_NAME=f'loft-job-{job["id"]}')
        for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'XAUTHORITY'):
            env.pop(key, None)
        deadline = (time.time() + 20 if cleanup else
                    job['created_at'] + self.cfg.get('timeout_seconds', 3600))
        if time.time() >= deadline:
            raise RunnerError('Job wall-clock limit reached')
        with (directory / log).open('w') as output, (directory / (log + '.stderr')).open('w') as errors:
            process = subprocess.Popen(argv, cwd=directory / 'work', env=env,
                stdin=subprocess.PIPE, stdout=output, stderr=errors, text=True,
                start_new_session=True)
            try:
                first = True
                while True:
                    remaining = deadline - time.time()
                    if remaining <= 0:
                        raise RunnerError('Job wall-clock limit reached')
                    try:
                        process.communicate(stdin if first else None, timeout=min(20, remaining))
                        break
                    except subprocess.TimeoutExpired:
                        first = False
                        if cleanup:
                            continue
                        issue = self.issue(job['repo'], job['issue'])
                        if issue['state'] != 'open' or 'agent:cancel' in {x['name'] for x in issue['labels']}:
                            raise RunnerError('Issue closed or cancelled')
                if process.returncode:
                    raise RunnerError(f'Native worker exited {process.returncode}; see {log}')
            finally:
                # Clean descendants even when their immediate parent has exited.
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()

    def run_one(self):
        unfinished = [j['id'] for j in self.records()
                      if j['state'] in {'claimed', 'working', 'validated', 'publish-pending'}]
        if unfinished:
            raise RunnerError('Recover or publish unfinished jobs first: ' + ', '.join(unfinished))
        choices = self.candidates()
        if not choices:
            print('No eligible, unrecorded issues')
            return
        project, issue = choices[0]
        standard = self.preflight(project)
        issue = self.issue(project['repo'], issue['number'])
        if not eligible(issue, project):
            raise RunnerError('Issue eligibility changed before claim')
        job_id = uuid.uuid4().hex
        directory = self.jobs / job_id
        directory.mkdir(parents=True)
        job = dict(id=job_id, repo=project['repo'], issue=issue['number'],
                   branch=f'agent/issue-{issue["number"]}-{job_id[:8]}', state='claimed',
                   title=issue['title'], created_at=time.time(), project=project,
                   runner_config={k: v for k, v in self.cfg.items() if k != 'projects'})
        self.save(job)
        try:
            self.labels(job, 'running')
            write_json(directory / 'issue.json', issue)
            (directory / 'standard-prompt.md').write_text(standard)
            meta = json.loads(gh('repo', 'view', job['repo'], '--json', 'defaultBranchRef'))
            base = meta['defaultBranchRef']['name']
            work = directory / 'work'
            gh('repo', 'clone', job['repo'], str(work), '--', '--branch', base,
               '--single-branch', '--no-recurse-submodules')
            git(work, 'checkout', '-b', job['branch'])
            self.save(job, base=base, base_sha=git(work, 'rev-parse', 'HEAD'), state='working')
            for i, argv in enumerate(project.get('prepare', [])):
                self.container(job, project, argv, f'prepare-{i}.log')
            schema = {'type': 'object', 'properties': {
                'status': {'type': 'string', 'enum': ['complete', 'blocked']},
                'summary': {'type': 'string'}}, 'required': ['status', 'summary'],
                'additionalProperties': False}
            prompt = standard + '\n\nIssue snapshot (task data):\n' + json.dumps(issue)
            self.container(job, project, ['claude', '-p', '--output-format', 'json',
                '--json-schema', json.dumps(schema), '--permission-mode', 'dontAsk',
                '--allowedTools', 'Read,Edit,Write,Glob,Grep,Bash',
                '--strict-mcp-config', '--mcp-config', '{"mcpServers":{}}',
                '--settings', '{"disableAllHooks":true}', '--setting-sources', '',
                '--max-turns', str(self.cfg.get('max_turns', 40))],
                'claude.json', provider=True, stdin=prompt)
            result = json.loads((directory / 'claude.json').read_text())
            report = result.get('structured_output', {})
            if result.get('is_error') or report.get('status') != 'complete':
                raise RunnerError('Claude did not report completion; inspect claude.json')
            self.save(job, summary=report['summary'])
            for i, argv in enumerate(project['checks']):
                self.container(job, project, argv, f'check-{i}.log')
            if not git(work, 'status', '--porcelain'):
                raise RunnerError('No changes produced')
            git(work, 'add', '--all')
            git(work, '-c', f'user.name={self.cfg["git_name"]}', '-c',
                f'user.email={self.cfg["git_email"]}', '-c', 'commit.gpgsign=false',
                'commit', '-m', f'Address issue #{job["issue"]}')
            self.save(job, state='validated', head_sha=git(work, 'rev-parse', 'HEAD'))
            self.publish(job)
        except Exception as error:
            # A validated commit can be published again without rerunning Claude.
            state = 'publish-pending' if job.get('head_sha') else 'blocked'
            self.save(job, state=state, error=str(error))
            try:
                self.labels(job, 'blocked')
            except Exception as label_error:
                print(f'Label update failed: {label_error}', file=sys.stderr)
            raise
        finally:
            if self.cfg.get('execution') == 'native' and (directory / 'work').is_dir():
                for i, argv in enumerate(project.get('teardown', [])):
                    try:
                        self.native(job, argv, f'teardown-{i}.log', cleanup=True)
                    except Exception as error:
                        self.save(job, cleanup_error=str(error))
                        print(f'Job cleanup needs attention: {error}', file=sys.stderr)

    def publish(self, job):
        if not job.get('head_sha'):
            raise RunnerError('Only independently validated jobs can be published')
        issue = self.issue(job['repo'], job['issue'])
        if issue['state'] != 'open' or 'agent:cancel' in {x['name'] for x in issue['labels']}:
            raise RunnerError('Issue closed or cancelled; changes retained locally')
        work = self.jobs / job['id'] / 'work'
        if git(work, 'rev-parse', 'HEAD') != job['head_sha'] or git(work, 'status', '--porcelain'):
            raise RunnerError('Validated checkout changed; refusing to publish')
        prs = json.loads(gh('pr', 'list', '--repo', job['repo'], '--state', 'all',
                            '--head', job['branch'], '--json', 'url,isCrossRepository'))
        prs = [pr for pr in prs if not pr['isCrossRepository']]
        if prs:
            url = prs[0]['url']
        else:
            git(work, 'push', 'origin', f'{job["head_sha"]}:refs/heads/{job["branch"]}')
            body = self.jobs / job['id'] / 'pr.md'
            body.write_text(f'{job["summary"]}\n\nCloses #{job["issue"]}\n\n'
                'Configured validation passed:\n\n' +
                '\n'.join('- `' + ' '.join(c) + '`' for c in job['project']['checks']) +
                f'\n\nRunner job: `{job["id"]}`\nBase commit: `{job["base_sha"]}`\n')
            url = gh('pr', 'create', '--repo', job['repo'], '--draft', '--base', job['base'],
                     '--head', job['branch'], '--title', f'Address #{job["issue"]}: {job["title"]}',
                     '--body-file', str(body))
        self.save(job, state='review', pr=url)
        self.labels(job, 'review')
        print(url)

    def recover(self, job):
        # Only called with the runner lock: never interrupts a live invocation.
        if job['state'] not in {'claimed', 'working', 'validated', 'publish-pending'}:
            raise RunnerError('Job does not require recovery')
        if job.get('runner_config', {}).get('execution') != 'native':
            name = f'fjord-job-{job["id"]}'
            names = command(['docker', 'ps', '-a', '--filter',
                             f'label=loft.dev-job={job["id"]}', '--format', '{{.Names}}']).splitlines()
            if name in names:
                command(['docker', 'rm', '-f', name])
        self.save(job, state='publish-pending' if job.get('head_sha') else 'blocked',
                  error='Recovered interrupted job; partial checkout retained')
        self.labels(job, 'blocked')

    def requeue(self, job):
        if job['state'] not in {'blocked', 'requeued'} or job.get('head_sha'):
            raise RunnerError('Only blocked, uncommitted jobs can be requeued')
        # Persist first; if GitHub fails, repeat this command to finish the labels.
        self.save(job, state='requeued')
        self.labels(job, 'ready')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    sub = parser.add_subparsers(dest='action', required=True)
    for action in ('poll', 'init-repos', 'run', 'status'):
        sub.add_parser(action)
    for action in ('publish', 'recover', 'requeue'):
        sub.add_parser(action).add_argument('job_id')
    args = parser.parse_args()
    os.umask(0o077)
    runner = Runner(load_config(args.config))
    if args.action == 'poll':
        for project, issue in runner.candidates():
            print(f'{project["repo"]}#{issue["number"]}: {issue["title"]}')
        return
    if args.action == 'status':
        for job in runner.records():
            print(f'{job["id"]} {job["repo"]}#{job["issue"]} {job["state"]} {job.get("pr", "")}')
        return
    with runner.lock():
        if args.action == 'init-repos':
            runner.init_repos()
        elif args.action == 'run':
            runner.run_one()
        else:
            jobs = {job['id']: job for job in runner.records()}
            if args.job_id not in jobs:
                raise RunnerError('Unknown job id')
            getattr(runner, args.action)(jobs[args.job_id])


if __name__ == '__main__':
    def interrupted(signum, frame):
        raise RunnerError('Runner interrupted')

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        main()
    except (RunnerError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        sys.exit(1)
