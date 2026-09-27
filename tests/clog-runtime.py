#!/usr/bin/env python3
"""Exercise a supplied standalone archive on the real non-root Nginx/FPM configs.

Local only: uses disposable rootless Podman containers and a loopback test port.
Usage: python3 tests/clog-runtime.py /path/to/clog-standalone.tar.gz
"""
import hashlib
import http.client
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.parse
import uuid

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('stage', ROOT / 'services/clog/stage-release.py')
stager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stager)
PHP = 'docker.io/library/php:8.4.24-fpm-alpine'
NGINX = 'docker.io/library/nginx:1.30.4-alpine'


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs).stdout.strip()


def main(archive):
    names = ['loft-clog-test-' + uuid.uuid4().hex[:10] + suffix for suffix in ('-php', '-nginx')]
    with tempfile.TemporaryDirectory(prefix='loft-clog-test-') as tmp:
        root = Path(tmp)
        release = stager.stage(archive, hashlib.sha256(archive.read_bytes()).hexdigest(), root / 'releases')
        config = root / 'config'
        shutil.copytree(ROOT / 'services/clog', config)
        for directory in ('data', 'data/sessions', 'runtime'):
            (root / directory).mkdir(mode=0o700)
        common = ['--userns=keep-id:uid=1003,gid=1003', '--user', '1003:1003', '--read-only',
                  '--cap-drop=ALL', '--security-opt=no-new-privileges',
                  '--tmpfs=/tmp:mode=1777', '--pids-limit=32']
        php = [*common, '--network=none', '--memory=256m',
               '-e', 'CLOG_DB=/var/lib/clog/clog.sqlite',
               '-e', 'CLOG_SESSION_PATH=/var/lib/clog/sessions',
               '-e', 'CLOG_ORIGIN=https://clog.loft.hsimah.com',
               '-v', f'{release}:/opt/clog:ro,z', '-v', f'{root}/data:/var/lib/clog:z',
               '-v', f'{root}/runtime:/run/clog:z',
               '-v', f'{config}/php-fpm.conf:/usr/local/etc/clog-fpm.conf:ro,z',
               '-v', f'{config}/php.ini:/usr/local/etc/php/conf.d/zz-clog.ini:ro,z',
               '-v', f'{config}/health.php:/usr/local/lib/clog-health.php:ro,z']
        try:
            run('podman', 'run', '--rm', *php, PHP, 'php', '/opt/clog/server/standalone/cli.php', 'install')
            run('podman', 'run', '--rm', '-i', *php, PHP, 'php', '/opt/clog/server/standalone/cli.php',
                'user:add', 'runtime-test', 'editor', input='disposable-test-password-2026')
            run('podman', 'run', '-d', '--name', names[0], *php, PHP, 'php-fpm',
                '--nodaemonize', '--fpm-config', '/usr/local/etc/clog-fpm.conf')
            run('podman', 'run', '-d', '--name', names[1], *common, '--memory=48m',
                '-p', '127.0.0.1::8080',
                '-v', f'{config}/nginx.conf:/etc/nginx/nginx.conf:ro,z',
                '-v', f'{config}/fastcgi.conf:/etc/nginx/clog-fastcgi.conf:ro,z',
                '-v', f'{release}/client/dist/assets:/srv/assets:ro,z',
                '-v', f'{root}/runtime:/run/clog:ro,z',
                '--entrypoint', 'nginx', NGINX, '-g', 'daemon off;')
            port = int(run('podman', 'port', names[1], '8080/tcp').rsplit(':', 1)[1])
            cookie = ''

            def request(path, method='GET', body=None, headers=None, host='clog.loft.hsimah.com'):
                nonlocal cookie
                conn = http.client.HTTPConnection('127.0.0.1', port, timeout=10)
                conn.request(method, path, body, {'Host': host, 'Cookie': cookie, **(headers or {})})
                response = conn.getresponse()
                payload = response.read().decode(errors='replace')
                if value := response.getheader('Set-Cookie'):
                    cookie = value.split(';', 1)[0]
                result = response.status, dict(response.getheaders()), payload
                conn.close()
                return result

            for attempt in range(30):
                try:
                    if request('/healthz')[0] == 200:
                        break
                except (OSError, http.client.HTTPException):
                    pass
                time.sleep(0.2)
            else:
                raise AssertionError('App did not become ready')
            run('podman', 'exec', names[0], 'php', '/usr/local/lib/clog-health.php')
            assert request('/healthz', host='unknown.invalid')[0] == 404
            for path in ('/.env', '/server/vendor/autoload.php', '/clog.sqlite', '/assets/evil.php', '/assets/missing.js'):
                assert request(path)[0] == 404, path
            assert request('/graphql', 'POST', '{}', {'Content-Type': 'application/json'})[0] == 401
            status, headers, login = request('/auth/login')
            assert status == 200 and 'no-store' in headers['Cache-Control']
            csrf = re.search(r'name="csrf" value="([^"]+)"', login).group(1)
            body = urllib.parse.urlencode({'username': 'runtime-test', 'password': 'disposable-test-password-2026', 'csrf': csrf})
            status, headers, _ = request('/auth/login', 'POST', body, {'Content-Type': 'application/x-www-form-urlencoded'})
            assert status == 303
            assert 'secure' in headers['Set-Cookie'].lower() and 'httponly' in headers['Set-Cookie'].lower()
            session = json.loads(request('/auth/session')[2])
            assert session['canWrite'] and session['userId'] != '0'
            assert request('/graphql', 'POST', '{"query":"{ __typename }"}', {'Content-Type': 'application/json'})[0] == 403
            status, _, payload = request('/graphql', 'POST', '{"query":"{ __typename }"}',
                                          {'Content-Type': 'application/json', 'X-Clog-CSRF': session['nonce']})
            assert status == 200 and 'data' in json.loads(payload), payload
            status, _, html = request('/items')
            assert status == 200 and 'type="module"' in html
            for asset in re.findall(r'(?:src|href)="(/assets/[^"?]+)', html):
                assert request(asset)[0] == 200, asset
            assert request('/graphql', 'POST', 'x' * 65537, {'Content-Type': 'application/json'})[0] == 413
            assert request('/auth/logout', 'POST', '', {'X-Clog-CSRF': session['nonce']})[0] == 200
            assert json.loads(request('/auth/session')[2])['userId'] == '0'
            statuses = [request('/auth/login', headers={'X-Clog-Client-IP': f'203.0.113.{i}'})[0] for i in range(10)]
            assert 429 in statuses, 'Forged client IP headers bypassed throttling'
            run('podman', 'run', '--rm', *php, PHP, 'php', '/opt/clog/server/standalone/cli.php', 'backup', '/var/lib/clog/backup.sqlite')
            assert (root / 'data/backup.sqlite').is_file()
            print('PASS: packaged app, health, login/CSRF/logout, deep links/assets, denied paths, body limit, throttling, backup')
        finally:
            for name in reversed(names):
                subprocess.run(['podman', 'logs', '--tail', '5', name], capture_output=True)
                subprocess.run(['podman', 'rm', '-f', name], capture_output=True)


if __name__ == '__main__':
    try:
        main(Path(sys.argv[1]).resolve())
    except subprocess.CalledProcessError as error:
        print(error.stderr, file=sys.stderr)
        raise
