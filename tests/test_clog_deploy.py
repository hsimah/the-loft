"""Exercise deployment ordering and failure recovery with disposable SQLite data."""
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('clog_deploy', ROOT / 'control-plane/clog-deploy.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FixtureDeployment(module.Deployment):
    def __init__(self, root, system):
        super().__init__(root, system)
        self.calls = []
        self.fail_at = None

    def preflight(self):
        self.calls.append(('preflight',))

    def credentials(self, username):
        return None if self.editor_count() else ('fixture-editor', 'disposable-password')

    def stage(self, archive):
        self.calls.append(('stage',))
        if self.fail_at == 'checksum':
            raise ValueError('checksum mismatch')
        self.target.mkdir(parents=True, exist_ok=True)
        return self.target

    def prepare_storage(self):
        for directory in (self.data, self.data / 'sessions', self.runtime):
            directory.mkdir(parents=True, exist_ok=True)

    def run(self, args, *, release=None, capture=False, input=None):
        args = tuple(map(str, args))
        self.calls.append(args)
        if 'pull' in args and self.fail_at == 'pull':
            raise ValueError('pull failed')
        if args[0] == 'curl':
            if args[-1].endswith('/healthz'):
                return '{"ok":false}' if self.fail_at == 'health' else '{"ok":true}'
            return 'OK'
        if 'config' in args and 'json' in args:
            return json.dumps({'services': {'clog': {'image': 'nginx:test'}, 'mushr': {'image': 'caddy:test'}}})
        if 'clog-cli' in args:
            command = args[args.index('clog-cli') + 1:]
            if command[0] == 'install':
                with sqlite3.connect(self.data / 'clog.sqlite') as db:
                    db.execute('CREATE TABLE IF NOT EXISTS clog_users (username TEXT, role TEXT, enabled INT)')
                    db.execute('CREATE TABLE IF NOT EXISTS inventory (name TEXT)')
                if self.fail_at == 'install':
                    raise ValueError('schema failed')
            elif command[0] == 'user:add':
                with sqlite3.connect(self.data / 'clog.sqlite') as db:
                    db.execute('INSERT INTO clog_users VALUES (?, ?, 1)', (command[1], command[2]))
            elif command[0] == 'backup':
                if self.fail_at == 'backup':
                    raise ValueError('backup failed')
                with sqlite3.connect(self.data / 'clog.sqlite') as src:
                    with sqlite3.connect(self.data / Path(command[1]).name) as dst:
                        src.backup(dst)
        return ''


class DeployTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name)
        self.repo = base / 'repo'
        for path in ('hosts/viking', 'hosts/viking/overrides/mushr', 'services/clog'):
            (self.repo / path).mkdir(parents=True, exist_ok=True)
        for path in ('hosts/viking/clog-release.json', 'hosts/viking/overrides/mushr/Caddyfile',
                     'hosts/viking/overrides/mushr/docker-compose.override.yml'):
            shutil.copyfile(ROOT / path, self.repo / path)
        self.deploy = FixtureDeployment(self.repo, base / 'system')
        self.chown = patch.object(module.os, 'chown')
        self.chown.start()
        self.addCleanup(self.chown.stop)

    def install(self):
        self.deploy.deploy()

    def existing(self):
        self.install()
        with sqlite3.connect(self.deploy.data / 'clog.sqlite') as db:
            db.execute("INSERT INTO inventory VALUES ('existing item')")
        self.deploy.calls.clear()

    def calls_with(self, token):
        return [c for c in self.deploy.calls if token in c]

    def test_fresh_install_then_rerun_preserves_account_data_and_proxy(self):
        self.existing()
        self.install()
        with sqlite3.connect(self.deploy.data / 'clog.sqlite') as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM clog_users').fetchone()[0], 1)
            self.assertEqual(db.execute('SELECT name FROM inventory').fetchone()[0], 'existing item')
        self.assertFalse(self.calls_with('user:add'))
        stops = self.calls_with('stop')
        backups = self.calls_with('backup')
        self.assertLess(self.deploy.calls.index(stops[0]), self.deploy.calls.index(backups[0]))
        self.assertTrue(self.deploy.backup.is_file())
        proxy_starts = [c for c in self.calls_with('up') if c[-1] == 'mushr']
        self.assertNotIn('--force-recreate', proxy_starts[0])
        self.assertFalse(self.deploy.pending.exists())
        self.assertEqual(self.deploy.env_file.stat().st_mode & 0o777, 0o600)

    def test_download_or_pull_failure_leaves_running_deployment_untouched(self):
        self.existing()
        for failure in ('checksum', 'pull'):
            with self.subTest(failure=failure):
                self.deploy.calls.clear()
                self.deploy.fail_at = failure
                before = self.deploy.env_file.read_bytes()
                with self.assertRaises(ValueError):
                    self.install()
                self.assertFalse(self.calls_with('stop'))
                self.assertFalse(self.deploy.pending.exists())
                self.assertEqual(self.deploy.env_file.read_bytes(), before)

    def test_backup_failure_prevents_schema_change(self):
        self.existing()
        self.deploy.fail_at = 'backup'
        with self.assertRaises(ValueError):
            self.install()
        self.assertFalse(self.calls_with('install'))
        self.assertTrue(self.deploy.pending.exists())

    def test_migration_failure_keeps_backup_and_blocks_unsafe_retry(self):
        self.existing()
        record = self.deploy.record.read_bytes()
        self.deploy.fail_at = 'install'
        with self.assertRaises(ValueError):
            self.install()
        self.assertTrue(self.deploy.backup.is_file())
        self.assertEqual(json.loads(self.deploy.pending.read_text())['phase'], 'installing')
        self.assertEqual(self.deploy.record.read_bytes(), record)
        self.assertFalse([c for c in self.calls_with('up') if c[-1] == 'clog'])
        self.deploy.calls.clear()
        self.deploy.fail_at = None
        with self.assertRaisesRegex(ValueError, 'Unfinished deployment'):
            self.install()
        self.assertFalse(self.calls_with('stage'))

    def test_failed_health_stops_app_without_success_marker(self):
        self.deploy.fail_at = 'health'
        with self.assertRaises(ValueError):
            self.install()
        self.assertTrue(self.deploy.pending.exists())
        self.assertFalse(self.deploy.record.exists())
        self.assertIn('stop', self.deploy.calls[-1])

    def test_concurrent_apply_fails_before_deploying(self):
        self.deploy.state.mkdir(parents=True)
        with (self.deploy.state / 'clog.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(ValueError, 'Another Clog'):
                self.install()
        self.assertFalse(self.calls_with('stage'))

    def test_fresh_install_accepts_the_example_env_placeholder(self):
        self.deploy.env_file.write_text(f'CLOG_RELEASE_DIR={self.deploy.releases}/pending\n')
        self.install()
        self.assertEqual(self.deploy.current_release(), self.deploy.target)

    def test_existing_database_requires_known_release(self):
        self.deploy.data.mkdir(parents=True)
        (self.deploy.data / 'clog.sqlite').touch()
        with self.assertRaisesRegex(ValueError, 'no selected release'):
            self.install()
        self.assertFalse(self.calls_with('stage'))

    def test_plan_does_not_invoke_host_tools(self):
        binary = Path(self.tmp.name) / 'bin'
        binary.mkdir()
        for name in ('docker', 'curl', 'systemctl', 'nft', 'sudo'):
            path = binary / name
            path.write_text('#!/bin/sh\nexit 97\n')
            path.chmod(0o755)
        result = subprocess.run(['python3', str(ROOT / 'control-plane/clog-deploy.py'), '--plan'],
                                env=dict(os.environ, PATH=f'{binary}:{os.environ["PATH"]}'),
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        release = json.loads((ROOT / 'hosts/viking/clog-release.json').read_text())
        self.assertIn(f"SHA-256: {release['sha256']}", result.stdout)

    def test_invalid_manifest_is_rejected(self):
        path = self.repo / 'hosts/viking/clog-release.json'
        release = json.loads(path.read_text())
        release['url'] = 'http://example.com/unpinned.tar.gz'
        path.write_text(json.dumps(release))
        with self.assertRaises(ValueError):
            module.load_release(path)

class EntryPointTests(unittest.TestCase):
    def test_loft_ctl_routes_plan_without_sudo(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for directory in ('hosts/viking', 'control-plane', 'bin'):
                (root / directory).mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / 'loft-ctl', root / 'loft-ctl')
            shutil.copyfile(ROOT / 'control-plane/common.sh', root / 'control-plane/common.sh')
            (root / 'hosts/viking/host.conf').write_text('SERVICES=(mushr pawst clog)\n')
            for name, body in {
                'hostname': 'echo viking',
                'python3': 'printf "%s\\n" "$@"',
                'sudo': 'exit 97',
            }.items():
                path = root / 'bin' / name
                path.write_text('#!/bin/sh\n' + body + '\n')
                path.chmod(0o755)
            result = subprocess.run(['bash', str(root / 'loft-ctl'), 'deploy', 'clog', '--plan'],
                                    env=dict(os.environ, PATH=f'{root}/bin:{os.environ["PATH"]}'),
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('control-plane/clog-deploy.py\n--plan', result.stdout)

    def test_general_setup_skips_stateful_app_installation(self):
        section = (ROOT / 'setup.sh').read_text().split('# ─── 11. Deploy services', 1)[1]
        section = section.split('\n', 1)[1].split('# ─── 11a.', 1)[0]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'control-plane').mkdir()
            (root / 'control-plane/common.sh').write_text('compose_args_for() { echo "-f $1"; }\n')
            script = ('set -euo pipefail\ninfo() { echo "$*"; }\nwarn() { echo "$*"; }\n'
                      'docker() { echo "docker $*"; }\nSERVICES=(clog pawst)\n' + section)
            result = subprocess.run(['bash', '-c', script], text=True, capture_output=True,
                                    env=dict(os.environ, REPO_DIR=str(root)))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('loft-ctl deploy clog', result.stdout)
            calls = [line for line in result.stdout.splitlines() if line.startswith('docker ')]
            self.assertTrue(calls)
            self.assertTrue(all('clog' not in line for line in calls))
