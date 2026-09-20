"""Check effective host isolation, not just fragments of override YAML."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('docker'), 'Docker Compose CLI required')
class PlatformTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Compose versions differ on whether --no-env-resolution still checks
        # env_file existence. Use isolated empty files, never live host secrets.
        fixture = tempfile.TemporaryDirectory(prefix='loft-compose-tests-')
        cls.addClassCleanup(fixture.cleanup)
        cls.compose_root = Path(fixture.name)
        paths = [*ROOT.glob('services/*/docker-compose.yml'),
                 *ROOT.glob('hosts/*/overrides/*/docker-compose.override.yml')]
        for source in paths:
            target = cls.compose_root / source.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            (target.parent / '.env').touch()

    def config(self, host, service, public=False, profiles=""):
        args = ['docker', 'compose', '-f', f'services/{service}/docker-compose.yml',
                '-f', f'hosts/{host}/overrides/{service}/docker-compose.override.yml']
        if public:
            args += ['--profile', 'public']
        result = subprocess.run(args + ['config', '--no-env-resolution', '--format', 'json'], cwd=self.compose_root,
                                env=dict(os.environ, COMPOSE_PROFILES=profiles),
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_fjord_cannot_start_a_tunnel_or_inherit_lan_proxy(self):
        cfg = self.config('fjord', 'mushr')
        self.assertEqual(set(cfg['services']), {'mushr'})
        proxy = cfg['services']['mushr']
        self.assertNotIn('build', proxy)
        self.assertNotIn('extra_hosts', proxy)
        self.assertNotIn('loft-proxy', cfg['networks'])
        self.assertEqual(set(proxy['environment']), {'XDG_DATA_HOME', 'XDG_CONFIG_HOME'})
        self.assertEqual(proxy['ports'][0]['host_ip'], '192.168.86.30')
        self.assertEqual(len(proxy['volumes']), 1)

    def test_viking_tunnel_is_opt_in_and_has_no_app_network(self):
        default = self.config('viking', 'mushr')
        self.assertEqual(set(default['services']), {'mushr'})
        cfg = self.config('viking', 'mushr', public=True)
        self.assertEqual(set(cfg['services']), {'mushr', 'mushr-tunnel'})
        tunnel = cfg['services']['mushr-tunnel']
        self.assertEqual(set(tunnel['networks']), {'ingress'})
        self.assertNotIn('ports', tunnel)
        self.assertNotIn('environment', tunnel)
        self.assertEqual(cfg['services']['mushr']['ports'][0]['host_ip'], '127.0.0.1')

    def test_apps_are_separate_nonroot_and_unpublished(self):
        for host, environments in [('fjord', ['dev', 'test']), ('viking', ['prod'])]:
            apps = self.config(host, 'pawst')
            proxy = self.config(host, 'mushr')
            self.assertEqual(len(apps['services']), len(environments))
            used = []
            for app in apps['services'].values():
                self.assertNotIn('ports', app)
                self.assertNotIn('build', app)
                self.assertTrue(app['read_only'])
                self.assertEqual(app['user'], '1003:1003')
                self.assertIn('ALL', app['cap_drop'])
                self.assertIn('no-new-privileges:true', app['security_opt'])
                self.assertEqual(len(app['networks']), 1)
                net = next(iter(app['networks']))
                self.assertNotIn(net, used)
                used.append(net)
                self.assertTrue(proxy['networks'][net]['internal'])
                self.assertEqual(proxy['networks'][net]['name'], apps['networks'][net]['name'])
                self.assertTrue(apps['networks'][net]['external'])

    def test_viking_monitoring_never_starts_hub_services(self):
        for profiles in ('', 'metrics', 'hub', 'hub,metrics,public'):
            cfg = self.config('viking', 'houstn', profiles=profiles)
            self.assertEqual(set(cfg['services']), {'glances'})
            self.assertEqual(cfg['services']['glances']['network_mode'], 'host')

    def test_homepage_uses_viking_tailnet_address(self):
        cfg = self.config('space-needle', 'houstn', profiles='hub')
        entries = cfg['services']['homepage']['extra_hosts']
        hosts = dict(entry.split('=', 1) for entry in entries)
        self.assertEqual(len(entries), len(hosts), 'Duplicate host mappings are ambiguous')
        self.assertEqual(hosts['viking'], '100.119.43.53')
        self.assertEqual(hosts['fjord'], '192.168.86.30')
        self.assertEqual(hosts['woodstock'], '192.168.86.37')
        self.assertEqual(hosts['host.docker.internal'], 'host-gateway')

    def test_tailnet_policy_only_grants_management_and_monitoring(self):
        policy = json.loads((ROOT / 'hosts/viking/hardening/tailscale-policy.json').read_text())
        self.assertEqual(policy['acls'], [])
        self.assertEqual(policy['hosts']['blanco'], '100.92.100.36')
        self.assertEqual(policy['grants'], [
            {'src': ['blanco'], 'dst': ['tag:viking'], 'ip': ['tcp:22']},
            {'src': ['tag:monitoring'], 'dst': ['tag:viking'], 'ip': ['tcp:45876', 'tcp:61208']},
        ])

    def test_caddy_file_capability_exception_is_narrow(self):
        for host in ('fjord', 'viking'):
            cfg = self.config(host, 'mushr', public=host == 'viking')
            proxy = cfg['services']['mushr']
            self.assertEqual(proxy['user'], '1003:1003')
            self.assertEqual(proxy['cap_add'], ['NET_BIND_SERVICE'])
            self.assertEqual(proxy['cap_drop'], ['ALL'])
            self.assertTrue(proxy['read_only'])
            self.assertIn('no-new-privileges:true', proxy['security_opt'])
            # Commas in unquoted YAML flow lists split mount options into
            # separate mounts: Compose config accepts them, Docker rejects them.
            self.assertEqual(proxy['tmpfs'], ['/tmp:uid=1003,gid=1003,mode=1770'])
            for name, service in cfg['services'].items():
                if name != 'mushr':
                    self.assertFalse(service.get('cap_add'))
            for service in self.config(host, 'pawst')['services'].values():
                self.assertFalse(service.get('cap_add'))
                self.assertEqual(service['tmpfs'], ['/tmp:uid=1003,gid=1003,mode=1770'])
