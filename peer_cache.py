"""Authenticated, bounded LAN poster cache; compatible with Python 2.7/3."""
from __future__ import print_function
import hashlib
import hmac
import os
import re
import socket
import threading
try:
    from http.server import HTTPServer, BaseHTTPRequestHandler
    from urllib.request import Request, build_opener, ProxyHandler, HTTPRedirectHandler
except ImportError:
    from BaseHTTPServer import HTTPServer, BaseHTTPRequestHandler
    from urllib2 import Request, build_opener, ProxyHandler, HTTPRedirectHandler

PORT = 18742
MAX_BYTES = 8 * 1024 * 1024
NAME = re.compile(r'^poster-[a-f0-9]{64}\.(?:jpg|png)$')


def signature(secret, data):
    return hmac.new(secret.encode('utf-8'), data, hashlib.sha256).hexdigest()


def secret_for(config):
    if not config.get('peer_sharing', True):
        return ''
    return str(config.get('__metadata', {}).get('secrets', {}).get('account') or '')


def image_ok(data):
    return data.startswith(b'\xff\xd8\xff') or data.startswith(b'\x89PNG\r\n\x1a\n')


def poster_name(url):
    return 'poster-' + hashlib.sha256(url.encode('utf-8')).hexdigest() + ('.png' if url.endswith('.png') else '.jpg')


def private_ipv4(value):
    try:
        parts = [int(x) for x in value.split('.')]
        if len(parts) != 4 or any(x < 0 or x > 255 for x in parts):
            return False
        return parts[0] == 10 or (parts[0] == 172 and 16 <= parts[1] <= 31) or parts[:2] == [192, 168]
    except ValueError:
        return False


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def fetch(config, filename, destination):
    secret = secret_for(config)
    if not secret or not NAME.match(filename):
        return False
    # Explicit LAN addresses keep discovery traffic and public hosts out of scope.
    hosts = str(config.get('peer_addresses') or '').replace(',', ' ').split()[:8]
    opener = build_opener(ProxyHandler({}), NoRedirect())
    for host in hosts:
        if not private_ipv4(host):
            continue
        nonce = os.urandom(16).hex() if hasattr(bytes, 'hex') else __import__('binascii').hexlify(os.urandom(16)).decode('ascii')
        context = (filename + '\n' + nonce).encode('ascii')
        request = Request('http://%s:%d/%s' % (host, PORT, filename), headers={
            'X-Cinema-Nonce': nonce,
            'X-Cinema-Auth': signature(secret, context),
        })
        response = None
        try:
            response = opener.open(request, timeout=2)
            data = response.read(MAX_BYTES + 1)
            expected = signature(secret, context + b'\n' + data)
            received = response.headers.get('X-Cinema-Auth', '')
            if len(data) > MAX_BYTES or not image_ok(data) or not hmac.compare_digest(expected, received):
                continue
            temporary = destination + '.new'
            with open(temporary, 'wb') as handle:
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            os.rename(temporary, destination)
            print('poster retrieved from LAN peer %s' % host)
            return True
        except (IOError, OSError, ValueError, socket.error):
            continue
        finally:
            if response is not None:
                response.close()
    return False


def make_server(root, config_reader, address=('', PORT)):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def setup(self):
            self.request.settimeout(3)
            BaseHTTPRequestHandler.setup(self)

        def do_GET(self):
            secret = secret_for(config_reader())
            filename = self.path[1:]
            nonce = self.headers.get('X-Cinema-Nonce', '')
            if not secret or not NAME.match(filename) or not re.match(r'^[a-f0-9]{32}$', nonce):
                self.send_error(403)
                return
            context = (filename + '\n' + nonce).encode('ascii')
            if not hmac.compare_digest(signature(secret, context), self.headers.get('X-Cinema-Auth', '')):
                self.send_error(403)
                return
            path = os.path.join(root, filename)
            try:
                if os.path.islink(path):
                    raise IOError('symlink')
                with open(path, 'rb') as handle:
                    data = handle.read(MAX_BYTES + 1)
                if len(data) > MAX_BYTES or not image_ok(data):
                    raise IOError('invalid image')
            except IOError:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header('Content-Type', 'image/png' if filename.endswith('.png') else 'image/jpeg')
            self.send_header('Content-Length', str(len(data)))
            self.send_header('X-Cinema-Auth', signature(secret, context + b'\n' + data))
            self.end_headers()
            self.wfile.write(data)

    return HTTPServer(address, Handler)


def start(root, config_reader):
    try:
        server = make_server(root, config_reader)
        worker = threading.Thread(target=server.serve_forever)
        worker.daemon = True
        worker.start()
        return server
    except (IOError, OSError, socket.error) as error:
        print('LAN poster server unavailable; internet fallback remains active: %s' % error)
        return None
