"""Exercise the sourced helpers without a Docker daemon or network access."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HealthTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "control-plane").mkdir()
        shutil.copyfile(ROOT / "control-plane/common.sh", self.root / "control-plane/common.sh")
        host = self.root / "hosts/test-host"
        host.mkdir(parents=True)
        (host / "host.conf").write_text("HOST_NAME=test-host\n")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        commands = {
            "hostname": "printf test-host",
            "curl": 'printf "%s" "$MOCK_HTTP"; exit "$MOCK_CURL_EXIT"',
            "sleep": "exit 0",
            "docker": '''case " $* " in
  *" config --services "*) printf '%s\\n' "$MOCK_EXPECTED"; exit "${MOCK_CONFIG_EXIT:-0}" ;;
  *" ps --all --format "*) printf '%s\\n' "$MOCK_STATES"; exit "${MOCK_PS_EXIT:-0}" ;;
  *" ps --all "*) exit 0 ;;
  *) echo "Unexpected Docker command: $*" >&2; exit 99 ;;
esac''',
        }
        for name, body in commands.items():
            script = self.bin / name
            script.write_text("#!/bin/bash\n" + body + "\n")
            script.chmod(0o755)

    def run_helper(self, command, **variables):
        env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                   MOCK_HTTP="200", MOCK_CURL_EXIT="0",
                   MOCK_EXPECTED="web\ndb", MOCK_STATES="web|running|\ndb|running|healthy")
        env.update(variables)
        return subprocess.run(
            ["bash", "-c", 'source control-plane/common.sh\nHC_TIMEOUT=1\nHC_INTERVAL=1\n' + command],
            cwd=self.root, env=env, capture_output=True, text=True, timeout=5,
        )

    def test_connection_failure_does_not_become_000000_success(self):
        result = self.run_helper("check_url http://unused local", MOCK_HTTP="000", MOCK_CURL_EXIT="7")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("FAIL", result.stdout)
        self.assertNotIn("OK", result.stdout)

    def test_timeout_after_headers_is_still_failure(self):
        result = self.run_helper("check_url http://unused local", MOCK_HTTP="200", MOCK_CURL_EXIT="28")
        self.assertEqual(result.returncode, 1)

    def test_warn_only_transport_failure_does_not_fail_run(self):
        result = self.run_helper("check_url http://unused local true", MOCK_HTTP="000", MOCK_CURL_EXIT="7")
        self.assertEqual(result.returncode, 0)
        self.assertIn("WARNING", result.stdout)

    def test_zero_code_without_transport_error_is_not_a_response(self):
        result = self.run_helper("check_url http://unused local", MOCK_HTTP="000")
        self.assertEqual(result.returncode, 1)

    def test_http_responses_keep_documented_reachability_semantics(self):
        for status in ("200", "302", "401", "403", "502"):
            with self.subTest(status=status):
                result = self.run_helper("check_url http://unused local", MOCK_HTTP=status)
                self.assertEqual(result.returncode, 0)
                self.assertIn(f"HTTP {status}", result.stdout)

    def test_running_services_with_optional_healthchecks_pass(self):
        result = self.run_helper('check_containers "-f unused.yml" app')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_active_service_fails(self):
        result = self.run_helper('check_containers "-f unused.yml" app', MOCK_STATES="web|running|")
        self.assertEqual(result.returncode, 1)

    def test_inactive_cli_container_does_not_fail_active_services(self):
        result = self.run_helper('check_containers "-f unused.yml" app',
                                 MOCK_STATES="web|running|\ndb|running|healthy\ncli|exited|")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_stopped_starting_and_unhealthy_services_fail(self):
        for state in ("db|exited|", "db|running|starting", "db|running|unhealthy"):
            with self.subTest(state=state):
                result = self.run_helper('check_containers "-f unused.yml" app',
                                         MOCK_STATES="web|running|\n" + state)
                self.assertEqual(result.returncode, 1)

    def test_failed_replica_is_not_hidden_by_healthy_one(self):
        result = self.run_helper('check_containers "-f unused.yml" app',
                                 MOCK_EXPECTED="web",
                                 MOCK_STATES="web|running|healthy\nweb|exited|")
        self.assertEqual(result.returncode, 1)

    def test_empty_service_selection_fails(self):
        result = self.run_helper('check_containers "-f unused.yml" app', MOCK_EXPECTED="")
        self.assertEqual(result.returncode, 1)

    def test_docker_errors_cannot_pass(self):
        for variable in ("MOCK_CONFIG_EXIT", "MOCK_PS_EXIT"):
            with self.subTest(variable=variable):
                result = self.run_helper('check_containers "-f unused.yml" app', **{variable: "1"})
                self.assertEqual(result.returncode, 1)


if __name__ == "__main__":
    unittest.main()
