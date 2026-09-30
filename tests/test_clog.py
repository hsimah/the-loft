"""Release extraction and effective Clog isolation regressions."""
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
STAGER = ROOT / 'services/clog/stage-release.sh'


def stage(archive, digest, releases, reuse=False):
    """Run the stager; return the release path or raise ValueError with its error."""
    args = ['bash', str(STAGER), str(archive), digest, '--releases', str(releases)]
    result = subprocess.run(args + (['--reuse'] if reuse else []), text=True, capture_output=True)
    if result.returncode:
        raise ValueError(result.stderr.strip())
    return Path(result.stdout.strip())


class ReleaseTests(unittest.TestCase):
    def bundle(self, directory, extra=None):
        archive = directory / 'release.tar.gz'
        with tarfile.open(archive, 'w:gz') as out:
            for name in ('server/standalone/public/index.php', 'server/standalone/cli.php',
                         'server/vendor/autoload.php', 'client/dist/.vite/manifest.json',
                         'client/dist/assets/stylex.css'):
                info = tarfile.TarInfo(name)
                info.size = 2
                out.addfile(info, io.BytesIO(b'{}'))
            if extra:
                out.addfile(extra)
        return archive, hashlib.sha256(archive.read_bytes()).hexdigest()

    def test_valid_archive_is_immutable_and_readable(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            archive, digest = self.bundle(root)
            release = stage(archive, digest, root / 'releases')
            self.assertEqual(release.name, digest)
            self.assertEqual(release.stat().st_mode & 0o777, 0o755)
            with self.assertRaises(ValueError):
                stage(archive, digest, root / 'releases')

    def test_reuse_compares_the_existing_release_with_verified_archive(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            archive, digest = self.bundle(root)
            release = stage(archive, digest, root / 'releases')
            self.assertEqual(stage(archive, digest, root / 'releases', reuse=True), release)
            (release / 'server/standalone/cli.php').write_text('modified')
            with self.assertRaisesRegex(ValueError, 'differs'):
                stage(archive, digest, root / 'releases', reuse=True)

    def test_checksum_failure_does_not_stage(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            archive, _ = self.bundle(root)
            with self.assertRaises(ValueError):
                stage(archive, '0' * 64, root / 'releases')
            self.assertFalse((root / 'releases').exists())

    def test_traversal_and_links_are_rejected(self):
        for name, kind in [('../escaped', tarfile.REGTYPE),
                           ('/tmp/escaped', tarfile.REGTYPE),
                           ('server/link', tarfile.SYMTYPE),
                           ('server/hardlink', tarfile.LNKTYPE)]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                info = tarfile.TarInfo(name)
                info.type = kind
                info.linkname = '/etc/passwd' if kind != tarfile.REGTYPE else ''
                archive, digest = self.bundle(root, info)
                with self.assertRaises(ValueError):
                    stage(archive, digest, root / 'releases')
                self.assertEqual(list((root / 'releases').iterdir()), [])

class IsolationTests(unittest.TestCase):
    def test_effective_service_boundary(self):
        result = subprocess.run(['docker', 'compose', '-f', 'services/clog/docker-compose.yml',
                                 '--profile', 'tools', 'config', '--format', 'json'],
                                cwd=ROOT, text=True, capture_output=True, check=True)
        cfg = json.loads(result.stdout)
        self.assertEqual(set(cfg['services']), {'clog', 'clog-php', 'clog-cli'})
        for name, svc in cfg['services'].items():
            self.assertNotIn('ports', svc)
            self.assertNotIn('build', svc)
            self.assertTrue(svc['read_only'])
            self.assertEqual(svc['user'], '1003:1003')
            self.assertEqual(svc['cap_drop'], ['ALL'])
            mounts = {v['target']: v for v in svc['volumes']}
            if name == 'clog':
                self.assertEqual(set(svc['networks']), {'clog-prod'})
                self.assertNotIn('/var/lib/clog', mounts)
                self.assertNotIn('/opt/clog', mounts)
                self.assertTrue(mounts['/run/clog']['read_only'])
            else:
                self.assertEqual(svc['network_mode'], 'none')
                self.assertTrue(mounts['/opt/clog']['read_only'])
                self.assertFalse(mounts['/var/lib/clog'].get('read_only', False))
        self.assertTrue(cfg['networks']['clog-prod']['external'])
