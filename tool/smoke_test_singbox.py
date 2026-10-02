"""Local-only HY2/Clash probe integration; requires netlink-capable Linux (CI)."""
import hashlib
import http.client
import http.server
import json
import pathlib
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

binary = str(pathlib.Path(sys.argv[1]).resolve())
project = pathlib.Path(__file__).resolve().parents[1]
payload = bytes(range(256)) * 32768  # 8 MiB, deterministic integrity check

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/payload':
            self.send_response(200)
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        else:
            self.send_response(204)
            self.end_headers()
    def log_message(self, *args):
        pass

http_server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=http_server.serve_forever, daemon=True).start()
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
    udp.bind(('127.0.0.1', 0))
    udp_port = udp.getsockname()[1]

with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory)
    subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                    '-keyout', str(root/'key.pem'), '-out', str(root/'cert.pem'),
                    '-days', '1', '-subj', '/CN=localhost'],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['dart', 'run', 'tool/smoke_config.dart', str(root/'client.json'),
                    str(udp_port)], cwd=project, check=True)
    server_config = {'log': {'level': 'warn'}, 'inbounds': [{
        'type': 'hysteria2', 'listen': '127.0.0.1', 'listen_port': udp_port,
        'users': [{'password': 'test-password'}],
        'obfs': {'type': 'salamander', 'password': 'test-obfs'},
        'tls': {'enabled': True, 'certificate_path': str(root/'cert.pem'),
                'key_path': str(root/'key.pem')}}], 'outbounds': [{'type': 'direct'}]}
    (root/'server.json').write_text(json.dumps(server_config))
    processes = []
    logs = []
    def start(name):
        log = open(root/f'{name}.log', 'w')
        logs.append(log)
        process = subprocess.Popen([binary, 'run', '-c', str(root/f'{name}.json')],
                                   stdout=log, stderr=log)
        processes.append(process)
        return process
    def ready():
        for _ in range(60):
            try:
                with urllib.request.urlopen('http://127.0.0.1:9090/version', timeout=.2):
                    return
            except Exception:
                time.sleep(.1)
        raise RuntimeError('Clash API not ready')
    def delay():
        url = ('http://127.0.0.1:9090/proxies/proxy/delay?timeout=1500&url='
               f'http%3A%2F%2F127.0.0.1%3A{http_server.server_port}%2Fgenerate_204')
        with urllib.request.urlopen(url, timeout=3) as response:
            return json.load(response)
    try:
        start('server')
        client = start('client')
        ready()
        assert delay()['delay'] >= 0
        proxy = http.client.HTTPConnection('127.0.0.1', 10808, timeout=15)
        proxy.request('GET', f'http://127.0.0.1:{http_server.server_port}/payload')
        response = proxy.getresponse()
        assert response.status == 200
        actual = response.read()
        proxy.close()
        assert hashlib.sha256(actual).digest() == hashlib.sha256(payload).digest()
        print('PASS: HY2 TLS + salamander, real outbound delay, 8 MiB transfer integrity')
        client.terminate()
        client.wait(timeout=3)
        config = json.loads((root/'client.json').read_text())
        config['inbounds'] = []  # Match isolated offline-node probes.
        (root/'probe.json').write_text(json.dumps(config))
        probe = start('probe')
        ready()
        assert delay()['delay'] >= 0
        print('PASS: isolated node probe with no TUN or mixed listener')
        probe.terminate()
        probe.wait(timeout=3)
        config['outbounds'][0]['password'] = 'wrong-password'
        (root/'bad.json').write_text(json.dumps(config))
        start('bad')
        ready()
        try:
            value = delay()
            assert value.get('delay', -1) < 0, 'Wrong credentials returned a successful latency'
        except urllib.error.HTTPError:
            pass
        print('PASS: bad node authentication fails, no direct-network fallback')
    except Exception:
        for path in root.glob('*.log'):
            print(path.name, path.read_text()[-3000:], file=sys.stderr)
        raise
    finally:
        for p in processes:
            if p.poll() is None:
                p.terminate()
                try:
                    p.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    p.kill()
                    p.wait()
        for log in logs:
            log.close()
        http_server.shutdown()
