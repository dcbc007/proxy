"""Exercise generated Android config: DNS -> HY2 -> verified TLS -> HTTP.

Only the bootstrap DNS address/port is redirected to a local test DNS server.
No hosts entries or pre-resolved proxy IP can hide a missing domain resolver.
"""
import copy
import http.client
import http.server
import json
import pathlib
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request

binary = str(pathlib.Path(sys.argv[1]).resolve())
project = pathlib.Path(__file__).resolve().parents[1]
queries = []
dns = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
dns.bind(('127.0.0.1', 0))
dns.settimeout(.2)
stop = threading.Event()

def serve_dns():
    while not stop.is_set():
        try:
            packet, peer = dns.recvfrom(4096)
        except socket.timeout:
            continue
        pos, labels = 12, []
        while packet[pos]:
            size = packet[pos]
            labels.append(packet[pos+1:pos+1+size].decode())
            pos += size+1
        pos += 1
        qtype, qclass = struct.unpack('!HH', packet[pos:pos+4])
        name = '.'.join(labels)
        queries.append(name)
        answer = name == 'hy2.aurum.test' and qtype == 1
        flags = 0x8180 if name == 'hy2.aurum.test' else 0x8183
        response = packet[:2] + struct.pack('!HHHHH', flags, 1, int(answer), 0, 0)
        response += packet[12:pos+4]
        if answer:
            response += b'\xc0\x0c' + struct.pack('!HHIH', 1, 1, 0, 4)
            response += socket.inet_aton('127.0.0.1')
        dns.sendto(response, peer)

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        data = b'aurum-hy2-verified-dns-transfer'
        self.send_response(200)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *args):
        pass

httpd = http.server.HTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=serve_dns, daemon=True).start()
threading.Thread(target=httpd.serve_forever, daemon=True).start()
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
    sock.bind(('127.0.0.1', 0))
    hy_port = sock.getsockname()[1]

with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory)
    processes, handles = [], []
    def start(name, config):
        path = root / (name+'.json')
        path.write_text(json.dumps(config))
        subprocess.run([binary, 'check', '-c', str(path)], check=True)
        handle = open(root/(name+'.log'), 'w')
        handles.append(handle)
        proc = subprocess.Popen([binary, 'run', '-c', str(path)], stdout=handle, stderr=handle)
        processes.append(proc)
        return proc
    def end(proc):
        proc.terminate()
        proc.wait(timeout=5)
    def transfer():
        proxy = http.client.HTTPConnection('127.0.0.1', 10808, timeout=8)
        try:
            proxy.request('GET', f'http://127.0.0.1:{httpd.server_port}/')
            response = proxy.getresponse()
            return response.status == 200 and response.read() == b'aurum-hy2-verified-dns-transfer'
        finally:
            proxy.close()
    def ready(proc):
        for _ in range(100):
            assert proc.poll() is None, 'core exited during startup'
            try:
                with urllib.request.urlopen('http://127.0.0.1:9090/version', timeout=.2):
                    return
            except Exception:
                time.sleep(.1)
        raise RuntimeError('core API not ready')
    try:
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                        '-keyout', str(root/'key.pem'), '-out', str(root/'ca.pem'),
                        '-days', '1', '-subj', '/CN=hy2.aurum.test',
                        '-addext', 'subjectAltName=DNS:hy2.aurum.test'],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['dart', 'run', 'tool/smoke_bootstrap_config.dart',
                        str(root/'generated.json'), str(hy_port), str(root/'ca.pem')],
                       cwd=project, check=True)
        client = json.loads((root/'generated.json').read_text())
        assert client['route']['default_domain_resolver'] == 'dns-bootstrap'
        assert client['outbounds'][0]['server'] == 'hy2.aurum.test'
        assert client['outbounds'][0]['tls'].get('insecure', False) is False
        # Replace only the DNS fixture endpoint, retaining generated resolver wiring.
        resolver = client['dns']['servers'][0]
        assert resolver['server'] == '223.5.5.5' and not resolver.get('detour')
        resolver['server'], resolver['server_port'] = dns.getsockname()
        server = {'log': {'level': 'warn'}, 'inbounds': [{
            'type': 'hysteria2', 'listen': '127.0.0.1', 'listen_port': hy_port,
            'users': [{'password': 'bootstrap-test-password'}],
            'tls': {'enabled': True, 'certificate_path': str(root/'ca.pem'),
                    'key_path': str(root/'key.pem')}}], 'outbounds': [{'type': 'direct'}]}
        start('server', server)
        for name in ['strict', 'insecure', 'wrong-name', 'unknown-ca']:
            config = copy.deepcopy(client)
            tls = config['outbounds'][0]['tls']
            if name == 'insecure':
                tls['insecure'] = True
            elif name == 'wrong-name':
                tls['server_name'] = 'wrong.aurum.test'
            elif name == 'unknown-ca':
                config.pop('certificate')
            before = len(queries)
            proc = start(name, config)
            ready(proc)
            try:
                success = transfer()
            except (OSError, http.client.HTTPException):
                success = False
            assert success == (name in ['strict', 'insecure']), name
            assert 'hy2.aurum.test' in queries[before:], 'bootstrap DNS was not exercised'
            end(proc)
            if name in ['wrong-name', 'unknown-ca']:
                log = (root/(name+'.log')).read_text()
                assert 'x509' in log or 'certificate' in log, log
            print('PASS: HY2 bootstrap DNS + '+name)
    except Exception:
        for path in root.glob('*.log'):
            print(path.name, path.read_text()[-4000:], file=sys.stderr)
        raise
    finally:
        for proc in processes:
            if proc.poll() is None:
                end(proc)
        for handle in handles:
            handle.close()
        stop.set()
        httpd.shutdown()
