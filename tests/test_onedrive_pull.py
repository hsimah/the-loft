"""Exercise the OneDrive puller's safety invariants with a mocked rclone."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

try:
    import yaml
except ImportError:  # pragma: no cover - CI installs python3-yaml
    yaml = None

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "control-plane/onedrive-pull.sh"


class OneDrivePullTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.dest = self.root / "staging"
        self.state = self.root / "state"
        self.config = self.root / "rclone.conf"
        self.config.write_text("[onedrive]\ntype = onedrive\n")
        self.argv_log = self.root / "rclone-argv"

        self.bin = self.root / "bin"
        self.bin.mkdir()
        self._mock("rclone", f'''printf '%s\\n' "$*" >> "{self.argv_log}"
if [ -n "${{MOCK_RCLONE_CREATES:-}}" ]; then
  mkdir -p "$3" && : > "$3/${{MOCK_RCLONE_CREATES}}"
fi
exit "${{MOCK_RCLONE_EXIT:-0}}"''')

    def _mock(self, name, body):
        script = self.bin / name
        script.write_text("#!/bin/bash\n" + body + "\n")
        script.chmod(0o755)

    def run_pull(self, **variables):
        env = dict(
            os.environ,
            PATH=f"{self.bin}:{os.environ['PATH']}",
            ONEDRIVE_PULL_REMOTE="onedrive:Pictures",
            ONEDRIVE_PULL_DEST=str(self.dest),
            ONEDRIVE_PULL_CONFIG=str(self.config),
            ONEDRIVE_PULL_STATE_DIR=str(self.state),
        )
        env.update({k: str(v) for k, v in variables.items()})
        return subprocess.run(["bash", str(SCRIPT)], env=env,
                              text=True, capture_output=True)

    def rclone_argv(self):
        return self.argv_log.read_text() if self.argv_log.exists() else ""

    def test_copies_and_never_syncs(self):
        """`sync` would propagate OneDrive deletions onto the only local copy."""
        result = self.run_pull()
        self.assertEqual(result.returncode, 0, result.stderr)
        argv = self.rclone_argv()
        self.assertIn("copy onedrive:Pictures", argv)
        self.assertNotIn("sync", argv)
        self.assertIn(f"--config {self.config}", argv)

    def test_refuses_to_run_without_a_config(self):
        self.config.unlink()
        result = self.run_pull()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No rclone config", result.stdout + result.stderr)
        self.assertEqual(self.rclone_argv(), "")

    def test_refuses_an_unset_remote(self):
        result = self.run_pull(ONEDRIVE_PULL_REMOTE="")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.rclone_argv(), "")

    def test_concurrent_run_exits_without_pulling(self):
        """The first pull runs for hours while the 10-minute cron keeps firing."""
        self.state.mkdir(parents=True)
        lock = self.state / "pull.lock"
        lock.touch()
        holder = subprocess.Popen(["flock", str(lock), "sleep", "30"])
        self.addCleanup(holder.wait)
        self.addCleanup(holder.kill)
        # Let flock actually acquire before the contending run starts.
        subprocess.run(["flock", "--wait", "5", str(lock), "true"], check=False)
        result = self.run_pull()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.rclone_argv(), "")

    def test_failure_is_not_recorded_as_success(self):
        result = self.run_pull(MOCK_RCLONE_EXIT=7)
        self.assertEqual(result.returncode, 7)
        self.assertFalse((self.state / "last-success").exists())
        self.assertIn("next tick resumes", result.stdout)

    def test_reports_the_drain_complete_signal(self):
        """Operators stop the migration on repeated '0 new files' runs."""
        result = self.run_pull()
        self.assertIn("Up to date", result.stdout)
        self.assertTrue((self.state / "last-success").exists())

        result = self.run_pull(MOCK_RCLONE_CREATES="photo.jpg")
        self.assertIn("Added 1 file(s)", result.stdout)


class ManifestTests(unittest.TestCase):
    """host.conf and the Compose file have to agree on the host paths."""

    def setUp(self):
        self.conf = (ROOT / "hosts/space-needle/host.conf").read_text()
        self.compose = (ROOT / "services/hubbl/docker-compose.yml").read_text()

    def test_hubbl_paths_are_provisioned(self):
        for path in ("/opt/hubbl/db", "/mammoth/hubbl/library",
                     "/mammoth/hubbl/staging"):
            self.assertIn(path, self.conf, f"{path} is not in host.conf")
            self.assertIn(path, self.compose, f"{path} is not mounted")

    def test_staging_is_mounted_read_only(self):
        """A repeated import must not be able to damage the source photos."""
        self.assertIn("/mammoth/hubbl/staging:/import:ro", self.compose)

    @unittest.skipIf(yaml is None, 'PyYAML required')
    def test_homepage_group_declares_a_tab(self):
        """An undeclared group silently vanishes from the whole dashboard."""
        config = ROOT / "services/houstn/homepage-config"
        groups = {k for entry in yaml.safe_load((config / "services.yaml").read_text())
                  for k in entry}
        layout = yaml.safe_load((config / "settings.yaml").read_text())["layout"]
        self.assertEqual(groups - set(layout), set())


if __name__ == "__main__":
    unittest.main()
