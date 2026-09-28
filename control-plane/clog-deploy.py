#!/usr/bin/env python3
"""Deploy the pinned standalone Clog release on Viking. No Git, DNS or boot edits."""
import argparse
from datetime import datetime, timezone
import fcntl
import getpass
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import socket
import sqlite3
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def atomic_text(path, text, mode=0o600):
    fd, name = tempfile.mkstemp(prefix='.clog-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as out:
            out.write(text)
            out.flush()
            os.fsync(out.fileno())
        os.chmod(name, mode)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def load_release(path):
    release = json.loads(path.read_text())
    if (not isinstance(release, dict) or set(release) != {'version', 'url', 'sha256'}
            or not all(isinstance(value, str) for value in release.values())
            or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', release['version'])
            or not re.fullmatch(r'[a-f0-9]{64}', release['sha256'])
            or release['url'] != f"https://github.com/hsimah/clog/releases/download/{release['version']}/clog-standalone.tar.gz"):
        raise ValueError('Invalid pinned Clog release manifest')
    return release


class Deployment:
    def __init__(self, root=ROOT, system=Path('/')):
        self.root = root
        self.system = system
        self.release = load_release(root / 'hosts/viking/clog-release.json')
        self.releases = system / 'opt/clog/releases'
        self.target = self.releases / self.release['sha256']
        self.data = system / 'var/lib/clog/data'
        self.runtime = system / 'var/lib/clog/runtime'
        self.state = system / 'var/lib/loft/deploy'
        self.env_file = root / 'services/clog/.env'
        self.pending = self.state / 'clog-pending.json'
        self.record = self.state / 'clog.json'
        self.backup = None

    def run(self, args, *, release=None, capture=False, input=None):
        env = dict(os.environ, COMPOSE_PROFILES='')
        if release is not None:
            env['CLOG_RELEASE_DIR'] = str(release)
        print('+ ' + ' '.join(map(str, args)), flush=True)
        result = subprocess.run(list(map(str, args)), env=env, text=True, input=input,
                                stdout=subprocess.PIPE if capture else None, check=True)
        return result.stdout.strip() if capture else ''

    def compose(self, service, *args, release=None, **kwargs):
        command = ['docker', 'compose', '--project-directory', self.root / 'services' / service,
                   '-f', self.root / 'services' / service / 'docker-compose.yml']
        override = self.root / 'hosts/viking/overrides' / service / 'docker-compose.override.yml'
        if override.exists():
            command += ['-f', override]
        return self.run([*command, *args], release=release, **kwargs)

    def cli(self, release, *args, input=None):
        return self.compose('clog', 'run', '--rm', '--no-deps', '-T', 'clog-cli',
                            *args, release=release, input=input)

    def current_release(self):
        if not self.env_file.exists():
            return None
        values = re.findall(r'^CLOG_RELEASE_DIR=(.+)$', self.env_file.read_text(), re.M)
        if len(values) != 1:
            raise ValueError('Expected one CLOG_RELEASE_DIR in services/clog/.env')
        current = Path(values[0].strip().strip('\"\''))
        if current == self.releases / 'pending' and not (self.data / 'clog.sqlite').exists():
            return None
        if (current.parent != self.releases or not re.fullmatch(r'[a-f0-9]{64}', current.name)
                or current.is_symlink() or not current.is_dir()):
            raise ValueError('Current release must be an existing checksum-named release directory')
        return current

    def preflight(self):
        if os.geteuid() != 0 or socket.gethostname() != 'viking':
            raise ValueError('Apply requires sudo on Viking; use --plan elsewhere')
        if not (self.system / 'etc/loft/dmz-ready').is_file():
            raise ValueError('Complete the Viking DMZ preparation first')
        for command in ('docker', 'curl', 'systemctl', 'nft'):
            if not shutil.which(command):
                raise ValueError(f'Missing command: {command}')
        self.run(['systemctl', 'is-active', '--quiet', 'loft-firewall.service'])
        for table in ('loft_host', 'loft_docker'):
            self.run(['nft', 'list', 'table', 'inet', table], capture=True)
        info = json.loads(self.run(['docker', 'info', '--format', '{{json .}}'], capture=True))
        if not info.get('MemoryLimit'):
            print('WARNING: Docker memory limits are not enforced. Boot settings are unchanged.')

    def stage(self, archive):
        spec = importlib.util.spec_from_file_location('stage_clog', self.root / 'services/clog/stage-release.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        if archive is None:
            with tempfile.TemporaryDirectory(prefix='clog-download-') as tmp:
                archive = Path(tmp) / 'clog.tar.gz'
                self.run(['curl', '--fail', '--location', '--proto', '=https', '--proto-redir', '=https',
                          '--connect-timeout', '20', '--max-time', '300', '--output', archive, self.release['url']])
                return module.stage(archive, self.release['sha256'], self.releases, reuse=True)
        return module.stage(archive, self.release['sha256'], self.releases, reuse=True)

    def prepare_storage(self):
        for directory in (self.data, self.data / 'sessions', self.runtime):
            if directory.is_symlink():
                raise ValueError(f'Refusing a symlink for writable storage: {directory}')
            directory.mkdir(parents=True, exist_ok=True)
            os.chown(directory, 1003, 1003)
            directory.chmod(0o700)

    def validate(self):
        self.compose('clog', '--profile', 'tools', 'config', '--quiet', release=self.target)
        self.compose('clog', '--profile', 'tools', 'pull', release=self.target)
        self.compose('mushr', 'config', '--quiet')
        self.compose('mushr', 'pull', 'mushr')
        self.compose('clog', 'run', '--rm', '--no-deps', '--entrypoint', 'php', 'clog-cli', '-r',
                     'foreach (["pdo_sqlite","mbstring","Zend OPcache"] as $e) { if (!extension_loaded($e)) exit(1); } require "/opt/clog/server/standalone/bootstrap.php";',
                     release=self.target)
        self.compose('clog', 'run', '--rm', '--no-deps', '--entrypoint', 'php-fpm', 'clog-cli',
                     '--test', '--fpm-config', '/usr/local/etc/clog-fpm.conf', release=self.target)
        # Validate without Compose run: a live Caddy owns the fixed network address.
        for service, image_service, config, destination, extra, args in (
            ('clog', 'clog', self.root / 'services/clog/nginx.conf', '/etc/nginx/nginx.conf',
             ['-v', f'{self.root}/services/clog/fastcgi.conf:/etc/nginx/clog-fastcgi.conf:ro'],
             ['nginx', '-t']),
            ('mushr', 'mushr', self.root / 'hosts/viking/overrides/mushr/Caddyfile', '/etc/caddy/Caddyfile',
             ['--cap-add', 'NET_BIND_SERVICE', '-e', 'XDG_DATA_HOME=/tmp/data', '-e', 'XDG_CONFIG_HOME=/tmp/config'],
             ['caddy', 'validate', '--config', '/etc/caddy/Caddyfile']),
        ):
            cfg = json.loads(self.compose(service, 'config', '--format', 'json', release=self.target, capture=True))
            image = cfg['services'][image_service]['image']
            self.run(['docker', 'run', '--rm', '--network', 'none', '--read-only', '--user', '1003:1003',
                      '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges',
                      '--tmpfs', '/tmp:uid=1003,gid=1003,mode=1770', '-v', f'{config}:{destination}:ro',
                      *extra, '--entrypoint', args[0], image, *args[1:]])

    def prepare_proxy(self):
        cfg = json.loads(self.compose('mushr', 'config', '--format', 'json', capture=True))
        content = (self.root / 'hosts/viking/overrides/mushr/Caddyfile').read_bytes()
        self.proxy_digest = hashlib.sha256(content + json.dumps(cfg, sort_keys=True).encode()).hexdigest()
        previous = json.loads(self.record.read_text()) if self.record.exists() else {}
        # Unknown state gets one controlled refresh. Subsequent runs preserve unchanged ingress.
        if previous.get('proxy_sha256') != self.proxy_digest:
            self.compose('mushr', 'up', '-d', '--no-deps', '--force-recreate', '--wait', '--wait-timeout', '120', 'mushr')
        else:
            self.compose('mushr', 'up', '-d', '--no-deps', '--wait', '--wait-timeout', '120', 'mushr')
        for host in ('hsimah.com', 'hbla.ke'):
            self.probe(host, '/')

    def probe(self, host, path):
        return self.run(['curl', '--noproxy', '*', '--fail-with-body', '--silent', '--show-error',
                         '--max-time', '10', '-H', f'Host: {host}', f'http://127.0.0.1:8080{path}'], capture=True)

    def editor_count(self):
        if not (self.data / 'clog.sqlite').exists():
            return 0
        with sqlite3.connect(f'file:{self.data}/clog.sqlite?mode=ro', uri=True) as db:
            return db.execute("SELECT COUNT(*) FROM clog_users WHERE enabled = 1 AND role = 'editor'").fetchone()[0]

    def credentials(self, username):
        if self.editor_count():
            return None
        if not sys.stdin.isatty():
            raise ValueError('No editor account: run interactively to create the first account')
        name = username or input('First Clog username: ').strip()
        if not re.fullmatch(r'[a-zA-Z0-9_.@-]{1,100}', name):
            raise ValueError('Invalid account name')
        while True:
            password = getpass.getpass('Password (12–72 bytes): ')
            if not 12 <= len(password.encode()) <= 72:
                print('Use a password between 12 and 72 bytes.')
                continue
            if password == getpass.getpass('Confirm password: '):
                return name, password
            print('Passwords did not match; try again.')

    def ensure_account(self, credentials):
        if self.editor_count():
            print('Existing editor account retained.')
        elif credentials:
            name, password = credentials
            self.cli(self.target, 'user:add', name, 'editor', input=password)
        else:
            raise ValueError('No enabled editor after installation')

    def write_pending(self, phase, current):
        atomic_text(self.pending, json.dumps({'phase': phase, 'release': self.release,
                    'previous_directory': str(current) if current else None,
                    'backup': str(self.backup) if self.backup else None}, indent=2) + '\n')

    def deploy(self, archive=None, username=None):
        self.preflight()
        self.state.mkdir(parents=True, exist_ok=True)
        with (self.state / 'clog.lock').open('a') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise ValueError('Another Clog deployment is running')
            if self.pending.exists():
                raise ValueError(f'Unfinished deployment: inspect {self.pending} and the recovery runbook first')
            current = self.current_release()
            if (self.data / 'clog.sqlite').exists() and current is None:
                raise ValueError('Existing database has no selected release; restore services/clog/.env first')
            credentials = self.credentials(username)
            self.stage(archive)
            self.prepare_storage()
            self.validate()
            self.prepare_proxy()
            # Mark the operation before stopping writes, so interruptions are visible.
            self.write_pending('stopping', current)
            try:
                self.compose('clog', 'stop', 'clog', 'clog-php', release=current or self.target)
                if (self.data / 'clog.sqlite').exists():
                    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
                    self.backup = self.data / f'pre-deploy-{stamp}.sqlite'
                    self.cli(current, 'backup', f'/var/lib/clog/{self.backup.name}')
                    if not self.backup.is_file():
                        raise ValueError('Backup command did not create its output file')
                    self.write_pending('backed-up', current)
                self.write_pending('installing', current)
                self.cli(self.target, 'install')
                self.ensure_account(credentials)
                credentials = None
                existing = self.env_file.read_text() if self.env_file.exists() else ''
                lines = [line for line in existing.splitlines() if not line.startswith('CLOG_RELEASE_DIR=')]
                owner = (self.env_file if self.env_file.exists() else self.root / 'services/clog').stat()
                atomic_text(self.env_file, '\n'.join([*lines, f'CLOG_RELEASE_DIR={self.target}']) + '\n')
                # Preserve ownership so the normal adminhabl loft-ctl can read it.
                os.chown(self.env_file, owner.st_uid, owner.st_gid)
                self.compose('clog', 'up', '-d', '--force-recreate', '--wait', '--wait-timeout', '180',
                             'clog-php', 'clog', release=self.target)
                if json.loads(self.probe('clog.hsimah.com', '/healthz')) != {'ok': True}:
                    raise ValueError('Unexpected Clog health response')
                self.probe('clog.hsimah.com', '/auth/login')
                for host in ('hsimah.com', 'hbla.ke'):
                    self.probe(host, '/')
                atomic_text(self.record, json.dumps({**self.release, 'directory': str(self.target),
                    'proxy_sha256': self.proxy_digest, 'backup': str(self.backup) if self.backup else None,
                    'deployed_at': datetime.now(timezone.utc).isoformat()}, indent=2) + '\n')
                self.pending.unlink()
            except BaseException:
                # A possibly migrated database must not be served by the old release.
                try:
                    self.compose('clog', 'stop', 'clog', 'clog-php', release=self.target)
                except Exception:
                    pass
                print(f'Deployment incomplete. Clog was stopped; inspect {self.pending}.', file=sys.stderr)
                raise
        print('Clog is healthy through Caddy: https://clog.hsimah.com')
        print('For a first public cutover: viking-prod → clog.hsimah.com → HTTP mushr:8080;')
        print('HTTP Host Header: clog.hsimah.com. Existing routes need no Cloudflare change.')
        if self.backup:
            print(f'Local backup: {self.backup}. Copy it to encrypted off-host storage.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', action='store_true', help='Print the deployment plan without host changes')
    parser.add_argument('--archive', type=Path, help='Use a local archive instead of downloading; checksum still required')
    parser.add_argument('--user', help='First editor username; ignored when an editor already exists')
    args = parser.parse_args()
    deploy = Deployment()
    if args.plan:
        print(f"Deploy Clog {deploy.release['version']} to Viking from {deploy.release['url']}")
        print(f"SHA-256: {deploy.release['sha256']}")
        print('Verify/stage release and images; validate configs; prepare private storage and Caddy.')
        print('Stop Clog writes; back up existing SQLite; install schema; create an editor only if needed.')
        print('Select release; recreate Clog; check origin and existing sites; record successful deployment.')
        print('No Git pull, Cloudflare changes, boot edits, reboot or automatic database rollback.')
        return
    deploy.deploy(args.archive, args.user)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, sqlite3.Error, subprocess.CalledProcessError) as error:
        sys.exit(f'ERROR: {error}')
