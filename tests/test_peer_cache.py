import os
import sys
import tempfile
import threading
import unittest
from unittest import mock
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import peer_cache


class PeerTests(unittest.TestCase):
    def test_transfer_wrong_account_and_missing_poster(self):
        with tempfile.TemporaryDirectory() as source, tempfile.TemporaryDirectory() as target:
            name = peer_cache.poster_name('https://image.tmdb.org/t/p/w780/a.jpg')
            data = b'\xff\xd8\xffexample-image'
            with open(os.path.join(source, name), 'wb') as handle:
                handle.write(data)
            config = {'__metadata': {'secrets': {'account': 'test-account'}}, 'peer_addresses': '127.0.0.1'}
            server = peer_cache.make_server(source, lambda: config, ('127.0.0.1', 0))
            worker = threading.Thread(target=server.serve_forever)
            worker.start()
            try:
                destination = os.path.join(target, name)
                with mock.patch.object(peer_cache, 'PORT', server.server_port), mock.patch.object(peer_cache, 'private_ipv4', return_value=True):
                    self.assertTrue(peer_cache.fetch(config, name, destination))
                    with open(destination, 'rb') as handle:
                        self.assertEqual(handle.read(), data)
                    wrong = dict(config, __metadata={'secrets': {'account': 'wrong'}})
                    self.assertFalse(peer_cache.fetch(wrong, name, destination))
                    self.assertFalse(peer_cache.fetch(config, peer_cache.poster_name('missing.jpg'), destination))
            finally:
                server.shutdown()
                server.server_close()
                worker.join()

    def test_validation(self):
        self.assertFalse(peer_cache.fetch({}, 'poster-test.jpg', '/unused'))
        self.assertFalse(peer_cache.fetch({'peer_sharing': False}, '../config.json', '/unused'))
        self.assertFalse(peer_cache.NAME.match('../config.json'))
        self.assertFalse(peer_cache.private_ipv4('8.8.8.8'))
        self.assertTrue(peer_cache.private_ipv4('192.168.1.12'))
        self.assertNotEqual(peer_cache.poster_name('a.jpg'), peer_cache.poster_name('b.jpg'))

    def test_unreachable_peer(self):
        config = {'__metadata': {'secrets': {'account': 'test'}}, 'peer_addresses': '192.168.1.12'}
        with mock.patch.object(peer_cache, 'build_opener') as opener:
            opener.return_value.open.side_effect = IOError('unreachable')
            self.assertFalse(peer_cache.fetch(config, peer_cache.poster_name('a.jpg'), '/unused'))

    def test_tampered_response_is_not_saved(self):
        config = {'__metadata': {'secrets': {'account': 'test'}}, 'peer_addresses': '192.168.1.12'}
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(peer_cache, 'build_opener') as opener:
            response = opener.return_value.open.return_value
            response.read.return_value = b'\xff\xd8\xfftampered'
            response.headers = {'X-Cinema-Auth': 'invalid'}
            destination = os.path.join(directory, 'image.jpg')
            self.assertFalse(peer_cache.fetch(config, peer_cache.poster_name('a.jpg'), destination))
            self.assertFalse(os.path.exists(destination))
