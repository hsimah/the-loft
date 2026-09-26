"""Exercise queue safety and publication with real Git and mocked external services."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('dev_runner', ROOT / 'control-plane/dev-runner.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

ISSUE = dict(number=12, title='Fix a thing $(touch SHOULD_NOT_EXIST)', body='Task body',
             state='open', user={'login': 'hsimah'}, created_at='2026-09-26T00:00:00Z',
             labels=[{'name': 'agent:ready'}, {'name': 'agent:claude'}])


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = dict(repo='hsimah/clog', authors=['hsimah'], image='test:1',
                            prepare=[], checks=[['test', '-f', 'fixed.txt']])
        self.cfg = dict(root=str(self.root / 'runner'), projects=[self.project],
                        git_name='Test runner', git_email='test@example.invalid')
        self.app = runner.Runner(self.cfg)

    def test_eligibility(self):
        self.assertTrue(runner.eligible(ISSUE, self.project))
        for label in ('agent:codex', 'agent:running', 'agent:review', 'agent:blocked', 'agent:cancel'):
            issue = copy.deepcopy(ISSUE)
            issue['labels'].append({'name': label})
            self.assertFalse(runner.eligible(issue, self.project))
        for change in ({'state': 'closed'}, {'user': {'login': 'stranger'}},
                       {'pull_request': {}}, {'labels': [{'name': 'agent:claude'}]}):
            self.assertFalse(runner.eligible(dict(ISSUE, **change), self.project))

    def test_poll_is_read_only_and_flattens_pages(self):
        with patch.object(runner, 'gh', return_value=json.dumps([[], [ISSUE]])) as api:
            self.assertEqual(len(self.app.candidates()), 1)
        self.assertFalse(self.app.root.exists())
        self.assertIn('--paginate', api.call_args.args)

    def test_record_prevents_duplicate_even_after_crash(self):
        directory = self.app.jobs / 'attempt'
        directory.mkdir(parents=True)
        runner.write_json(directory / 'job.json', dict(id='attempt', repo='hsimah/clog',
                                                      issue=12, state='working'))
        with patch.object(runner, 'gh', return_value=json.dumps([[ISSUE]])):
            self.assertEqual(self.app.candidates(), [])

    def test_lock_excludes_overlapping_runs(self):
        with self.app.lock():
            with self.assertRaises(runner.RunnerError):
                with runner.Runner(self.cfg).lock():
                    self.fail('Acquired duplicate lock')

    def test_disabled_run_fails_before_claim(self):
        with patch.object(self.app, 'candidates', return_value=[(self.project, ISSUE)]), \
                patch.object(self.app, 'labels') as labels:
            with self.assertRaisesRegex(runner.RunnerError, 'enabled'):
                self.app.run_one()
            labels.assert_not_called()
        self.assertFalse(self.app.jobs.exists())

    def native_job(self):
        self.cfg['execution'] = 'native'
        job = dict(id='native-test', repo='hsimah/clog', issue=12, created_at=time.time())
        (self.app.jobs / job['id'] / 'work').mkdir(parents=True)
        return job

    def test_native_runs_in_checkout_with_job_environment(self):
        job = self.native_job()
        with patch.dict(runner.os.environ, DISPLAY=':99', XAUTHORITY='/secret'):
            self.app.container(job, self.project, ['python3', '-c',
                'import os,sys; from pathlib import Path; '
                'assert "DISPLAY" not in os.environ; assert "XAUTHORITY" not in os.environ; '
                'Path("result").write_text(sys.stdin.read()); '
                'print(os.environ["COMPOSE_PROJECT_NAME"])'], 'native.log', stdin='task text')
        directory = self.app.jobs / job['id']
        self.assertEqual((directory / 'work/result').read_text(), 'task text')
        self.assertEqual((directory / 'native.log').read_text().strip(), 'loft-job-native-test')

    def test_native_timeout_stops_process(self):
        job = self.native_job()
        self.cfg['timeout_seconds'] = 0.1
        with patch.object(self.app, 'issue', return_value=ISSUE):
            with self.assertRaisesRegex(runner.RunnerError, 'wall-clock'):
                self.app.native(job, ['python3', '-c', 'import time; time.sleep(30)'], 'timeout.log')

    def test_native_failed_command_is_not_success(self):
        job = self.native_job()
        with self.assertRaisesRegex(runner.RunnerError, 'exited 3'):
            self.app.native(job, ['python3', '-c', 'raise SystemExit(3)'], 'failed.log')

    def test_native_observes_cancellation_during_work(self):
        job = self.native_job()
        self.cfg['timeout_seconds'] = 0.1
        issue = copy.deepcopy(ISSUE)
        issue['labels'].append({'name': 'agent:cancel'})
        with patch.object(self.app, 'issue', return_value=issue):
            with self.assertRaisesRegex(runner.RunnerError, 'cancelled'):
                self.app.native(job, ['python3', '-c', 'import time; time.sleep(30)'], 'cancel.log')

    def pipeline(self, *, fail_check=False, fail_publish=False):
        origin = self.root / 'origin'
        subprocess.run(['git', 'init', '-b', 'main', str(origin)], check=True, capture_output=True)
        (origin / 'README.md').write_text('Original\n')
        runner.git(origin, 'add', '.')
        runner.git(origin, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                   '-c', 'commit.gpgsign=false', 'commit', '-m', 'Initial')
        self.creates = 0
        self.pr_exists = False

        def gh(*args):
            if args[0] == 'api':
                return json.dumps(copy.deepcopy(ISSUE))
            if args[:2] == ('repo', 'view'):
                return json.dumps({'defaultBranchRef': {'name': 'main'}})
            if args[:2] == ('repo', 'clone'):
                subprocess.run(['git', 'clone', str(origin), args[3]], check=True, capture_output=True)
                return ''
            if args[:2] == ('pr', 'list'):
                self.assertNotIn(':', args[args.index('--head') + 1])
                return json.dumps([{'url': 'https://github.com/hsimah/clog/pull/99',
                                    'isCrossRepository': False}] if self.pr_exists else [])
            if args[:2] == ('pr', 'create'):
                self.creates += 1
                self.pr_exists = True
                if fail_publish:
                    raise runner.RunnerError('Connection lost after server created PR')
                return 'https://github.com/hsimah/clog/pull/99'
            return ''

        def container(job, project, argv, log, **kwargs):
            directory = self.app.jobs / job['id']
            if argv[0] == 'claude':
                (directory / 'work/fixed.txt').write_text('Fixed\n')
                (directory / log).write_text(json.dumps({'is_error': False,
                    'structured_output': {'status': 'complete', 'summary': 'Fixed the thing.'}}))
            elif fail_check:
                raise runner.RunnerError('Validation failed')

        return gh, container

    def test_end_to_end_and_publication_is_idempotent(self):
        gh, container = self.pipeline()
        with patch.object(self.app, 'candidates', return_value=[(self.project, ISSUE)]), \
                patch.object(self.app, 'preflight', return_value='Fix issue'), \
                patch.object(self.app, 'container', side_effect=container), patch.object(runner, 'gh', side_effect=gh):
            self.app.run_one()
            job = self.app.records()[0]
            self.assertEqual(job['state'], 'review')
            self.app.publish(job)
        self.assertEqual(self.creates, 1)
        self.assertFalse((self.root / 'SHOULD_NOT_EXIST').exists())

    def test_failed_validation_never_publishes(self):
        gh, container = self.pipeline(fail_check=True)
        with patch.object(self.app, 'candidates', return_value=[(self.project, ISSUE)]), \
                patch.object(self.app, 'preflight', return_value='Fix issue'), \
                patch.object(self.app, 'container', side_effect=container), patch.object(runner, 'gh', side_effect=gh):
            with self.assertRaisesRegex(runner.RunnerError, 'Validation failed'):
                self.app.run_one()
        self.assertEqual(self.creates, 0)
        self.assertEqual(self.app.records()[0]['state'], 'blocked')

    def test_publish_network_failure_recovers_without_agent_retry(self):
        gh, container = self.pipeline(fail_publish=True)
        with patch.object(self.app, 'candidates', return_value=[(self.project, ISSUE)]), \
                patch.object(self.app, 'preflight', return_value='Fix issue'), \
                patch.object(self.app, 'container', side_effect=container) as worker, \
                patch.object(runner, 'gh', side_effect=gh):
            with self.assertRaisesRegex(runner.RunnerError, 'Connection lost'):
                self.app.run_one()
            job = self.app.records()[0]
            self.assertEqual(job['state'], 'publish-pending')
            calls = worker.call_count
            self.app.publish(job)
            self.assertEqual(worker.call_count, calls)
        self.assertEqual(self.creates, 1)
        self.assertEqual(self.app.records()[0]['state'], 'review')


if __name__ == '__main__':
    unittest.main()
