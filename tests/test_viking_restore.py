"""Exercise recovery ordering and gates without changing the local host."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('jq'), 'jq required')
class VikingRestoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        host = self.root / 'hosts/viking'
        host.mkdir(parents=True)
        self.script = host / 'restore'
        text = (ROOT / 'hosts/viking/restore').read_text()
        text = text.replace('[[ $EUID -eq 0 ]]', '[[ 0 -eq 0 ]]')
        for path in ('/etc/loft/dmz-ready', '/var/backups/loft', '/var/lib/loft/deploy'):
            text = text.replace(path, str(self.root / path.lstrip('/')))
        self.script.write_text(text)
        self.manifest = host / 'releases.json'
        shutil.copy(ROOT / 'hosts/viking/releases.json', self.manifest)
        gate = self.root / 'etc/loft/dmz-ready'
        gate.parent.mkdir(parents=True)
        gate.touch()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        commands = {
            'hostname': 'echo viking',
            'id': 'echo 1003',
            'nft': 'exit 0',
            'systemctl': 'exit 0',
            'docker': '''printf '%s\\n' "$*" >> "$FIXTURE/docker-calls"
if [ "$1" = ps ] && [ "${RUNNING:-}" = tunnel ] && [ "$3" = 'name=^/mushr-tunnel$' ]; then echo mushr-tunnel; fi
exit 0''',
            'curl': '''case "$*" in *unknown.invalid*) printf 404;; esac''',
            'rsync': 'exit 0',
            'flock': 'exit 0',
        }
        for name, body in commands.items():
            path = self.bin / name
            path.write_text('#!/bin/bash\n' + body + '\n')
            path.chmod(0o755)
        control = self.root / 'control-plane'
        control.mkdir()
        (control / 'deploy-pull.sh').write_text(
            'printf "%s|%s\\n" "$LOFT_FORCE_DEPLOY" "$*" >> "$FIXTURE/deploy-calls"\n')
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}', FIXTURE=str(self.root))

    def run_restore(self, *args):
        return subprocess.run(['bash', str(self.script), *args], env=self.env,
                              capture_output=True, text=True)

    def test_default_plan_has_no_host_effects(self):
        result = self.run_restore()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('LOFT_FORCE_DEPLOY=1', result.stdout)
        self.assertIn('deploy-20260717201728-ad0a0ac', result.stdout)
        self.assertFalse((self.root / 'docker-calls').exists())
        self.assertFalse((self.root / 'deploy-calls').exists())
        self.assertFalse((self.root / 'var').exists())

    def test_bad_digest_fails_before_host_commands(self):
        manifest = json.loads(self.manifest.read_text())
        manifest['hblake']['sha256'] = 'not-a-digest'
        self.manifest.write_text(json.dumps(manifest))
        result = self.run_restore('--apply')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'docker-calls').exists())

    def test_active_tunnel_prevents_content_restore(self):
        self.env['RUNNING'] = 'tunnel'
        result = self.run_restore('--apply')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Stop mushr-tunnel', result.stderr)
        self.assertFalse((self.root / 'deploy-calls').exists())

    def test_restore_forces_pins_and_starts_only_local_services(self):
        state = self.root / 'var/lib/loft/deploy'
        state.mkdir(parents=True)
        marker = state / 'pawst-hblake.version'
        marker.write_text('old-release')
        result = self.run_restore('--apply')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = (self.root / 'deploy-calls').read_text().splitlines()
        self.assertEqual(len(calls), 2)
        self.assertTrue(all(line.startswith('1|pawst-') for line in calls))
        self.assertIn('hsimah-services/hblake /opt/pawst/prod/hblake', calls[0])
        docker = (self.root / 'docker-calls').read_text().splitlines()
        starts = [line for line in docker if 'up -d --wait' in line]
        self.assertEqual(len(starts), 2)
        self.assertTrue(starts[0].endswith('up -d --wait mushr'))
        self.assertTrue(starts[1].endswith('up -d --wait pawst'))
        backups = list((self.root / 'var/backups/loft').glob('*/pawst-hblake.version'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), 'old-release')
