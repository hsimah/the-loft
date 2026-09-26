"""Check the fleet config without command-line module overrides."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('fastfetch'), 'Fastfetch is not installed')
class FastfetchTests(unittest.TestCase):
    def test_config_displays_laiko_and_system_stats(self):
        config = json.loads((ROOT / 'fastfetch.jsonc').read_text())
        # Only relocate the installed asset; use the actual configured modules.
        config['logo']['source'] = str(ROOT / 'laiko.txt')
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'config.jsonc'
            path.write_text(json.dumps(config))
            result = subprocess.run(
                ['fastfetch', '--config', str(path), '--pipe', 'false'],
                capture_output=True, text=True, timeout=30,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        output = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', result.stdout)
        for line in (ROOT / 'laiko.txt').read_text().splitlines():
            self.assertIn(re.sub(r'\$[1-9]', '', line).rstrip(), output)
        for label in ('OS:', 'Kernel:', 'CPU:', 'Memory:'):
            self.assertIn(label, output)
