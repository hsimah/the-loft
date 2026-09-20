"""Run setup's real membership section with mocked account-management commands."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ProductionMembershipTests(unittest.TestCase):
    def run_membership(self, production, groups='pack-member docker', remove_status=0):
        script = (ROOT / 'setup.sh').read_text()
        section = script.split('# Ensure docker group memberships;', 1)[1]
        section = section.split('# ─── 10a.', 1)[0]
        # The first line is the remainder of the comment, not shell code.
        section = section.split('\n', 1)[1]
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            for name, body in {
                'id': 'printf "%s\\n" "$MOCK_GROUPS"',
                'gpasswd': 'printf "gpasswd %s\\n" "$*"; exit "$MOCK_REMOVE_STATUS"',
                'usermod': 'printf "usermod %s\\n" "$*"',
            }.items():
                tool = path / name
                tool.write_text('#!/bin/bash\n' + body + '\n')
                tool.chmod(0o755)
            return subprocess.run(['bash', '-c', 'set -euo pipefail\n' + section],
                                  env=dict(os.environ, PATH=f'{path}:{os.environ["PATH"]}',
                                           PRODUCTION_ROLE=production, MOCK_GROUPS=groups,
                                           MOCK_REMOVE_STATUS=str(remove_status)),
                                  capture_output=True, text=True)

    def test_production_removes_legacy_membership_and_preserves_admin(self):
        result = self.run_membership('true')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('gpasswd -d littledog docker', result.stdout)
        self.assertNotIn('usermod -aG docker littledog', result.stdout)
        self.assertIn('usermod -aG docker adminhabl', result.stdout)

    def test_production_is_idempotent_without_membership(self):
        result = self.run_membership('true', groups='pack-member')
        self.assertEqual(result.returncode, 0)
        self.assertNotIn('gpasswd', result.stdout)
        self.assertNotIn('littledog', result.stdout)

    def test_nonproduction_keeps_existing_behavior(self):
        result = self.run_membership('false')
        self.assertEqual(result.returncode, 0)
        self.assertIn('usermod -aG docker littledog', result.stdout)
        self.assertIn('usermod -aG docker adminhabl', result.stdout)

    def test_failed_removal_does_not_silently_continue(self):
        result = self.run_membership('true', remove_status=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('usermod', result.stdout)
