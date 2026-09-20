"""Run the real release puller against local fake GitHub responses."""
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(all(shutil.which(x) for x in ['jq', 'rsync', 'flock']), 'deployment utilities required')
class DeployTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.state = self.root / 'state'
        script = (ROOT / 'control-plane/deploy-pull.sh').read_text()
        script = script.replace('STATE_DIR="/var/lib/loft/deploy"', f'STATE_DIR="{self.state}"')
        self.script = self.root / 'deploy-pull.sh'
        self.script.write_text(script)
        shutil.copy(ROOT / 'control-plane/extract-release.py', self.root)
        auth = self.root / 'github-app-token.sh'
        auth.write_text('#!/bin/sh\nexit 1\n')
        auth.chmod(0o755)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        curl = self.bin / 'curl'
        curl.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$FIXTURE/calls"
while [[ $# -gt 0 ]]; do
  if [[ "$1" == -o ]]; then cp "$FIXTURE/asset.tar.gz" "$2"; exit; fi
  shift
done
cat "$FIXTURE/release.json"
''')
        curl.chmod(0o755)
        self.target = self.root / 'site'
        self.target.mkdir()
        (self.target / 'index.html').write_text('old')
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}', FIXTURE=str(self.root))

    def release(self, tag='v2', entries=None, count=1):
        entries = entries or [('site/index.html', b'new'), ('site/.hidden', b'preserved')]
        with tarfile.open(self.root / 'asset.tar.gz', 'w:gz') as tar:
            for name, value in entries:
                item = tarfile.TarInfo(name)
                if value is None:
                    item.type = tarfile.SYMTYPE
                    item.linkname = '/etc/passwd'
                    tar.addfile(item)
                else:
                    item.size = len(value)
                    tar.addfile(item, io.BytesIO(value))
        (self.root / 'release.json').write_text(json.dumps({'tag_name': tag, 'assets': [
            {'name': f'asset-{i}.tar.gz', 'url': 'https://fixture/asset'} for i in range(count)]}))
        return hashlib.sha256((self.root / 'asset.tar.gz').read_bytes()).hexdigest()

    def deploy(self, tag, digest):
        return subprocess.run(['bash', str(self.script), 'test-site', 'owner/repo',
                               str(self.target), '', tag, digest], env=self.env,
                              text=True, capture_output=True)

    def test_promotion_and_older_release_rollback_preserve_mount_inode(self):
        inode = self.target.stat().st_ino
        digest = self.release()
        result = self.deploy('v2', digest)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.target / '.hidden').read_text(), 'preserved')
        self.assertEqual(self.target.stat().st_ino, inode)
        digest = self.release('v1', [('index.html', b'known-good')])
        result = self.deploy('v1', digest)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.target / 'index.html').read_text(), 'known-good')
        self.assertFalse((self.target / '.hidden').exists())
        self.assertIn('/releases/tags/v1', (self.root / 'calls').read_text())
        self.assertEqual((self.state / 'test-site.version').read_text().strip(), 'v1')

    def test_checksum_failure_leaves_content_and_state_unchanged(self):
        self.release()
        result = self.deploy('v2', '0' * 64)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.target / 'index.html').read_text(), 'old')
        self.assertFalse((self.state / 'test-site.version').exists())

    def test_unsafe_or_incomplete_archives_never_reach_target(self):
        for entries in [[('../escape', b'bad')], [('index.html', None)], [('data.txt', b'no index')]]:
            with self.subTest(entries=entries):
                digest = self.release(entries=entries)
                result = self.deploy('v2', digest)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual((self.target / 'index.html').read_text(), 'old')
                self.assertFalse((self.root / 'escape').exists())

    def test_ambiguous_assets_and_tag_mismatch_fail(self):
        digest = self.release(count=2)
        self.assertNotEqual(self.deploy('v2', digest).returncode, 0)
        digest = self.release(tag='v3')
        self.assertNotEqual(self.deploy('v2', digest).returncode, 0)

    def test_pinned_release_requires_checksum(self):
        self.release()
        self.assertNotEqual(self.deploy('v2', '').returncode, 0)
        self.assertFalse((self.root / 'calls').exists())

    def test_production_host_refuses_latest(self):
        hostname = self.bin / 'hostname'
        hostname.write_text('#!/bin/sh\nprintf test-production\n')
        hostname.chmod(0o755)
        # Match the real script's control-plane/../hosts layout.
        control = self.root / 'control-plane'
        control.mkdir()
        copied = control / 'deploy-pull.sh'
        shutil.copy(self.script, copied)
        manifest = self.root / 'hosts/test-production'
        manifest.mkdir(parents=True)
        (manifest / 'host.conf').write_text('PRODUCTION_ROLE=true\n')
        self.script = copied
        result = self.deploy('', '')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Production deployments require', result.stderr)
        self.assertFalse((self.root / 'calls').exists())

    def test_concurrent_deployment_is_rejected(self):
        import fcntl
        self.state.mkdir()
        digest = self.release()
        with (self.state / 'test-site.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.deploy('v2', digest)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Another deployment', result.stdout)
        self.assertEqual((self.target / 'index.html').read_text(), 'old')
