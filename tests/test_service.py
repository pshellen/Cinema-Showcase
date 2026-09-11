import importlib.machinery
import json
import os
import sys
import tempfile
import unittest
from unittest import mock
from io import BytesIO


PACKAGE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PACKAGE)
service = importlib.machinery.SourceFileLoader("cinema_hub_service", os.path.join(PACKAGE, "service")).load_module()


class ServiceTests(unittest.TestCase):
    def test_poster_peer_miss_downloads_from_tmdb(self):
        with tempfile.TemporaryDirectory() as directory:
            config = {'indy_feed_url': '', 'show_qr_codes': False, 'manual_movies': [
                {'title': 'Example', 'tmdb_id': 42, 'poster_path': '/example.jpg'}]}
            with mock.patch.object(service, 'ROOT', directory), mock.patch.object(service, 'SCRATCH', directory), mock.patch.object(service, 'CATALOG', os.path.join(directory, 'catalog.json')), mock.patch.object(service.peer_cache, 'fetch', return_value=False) as peer, mock.patch.object(service, 'download') as download:
                service.refresh(config)
                peer.assert_called_once()
                self.assertEqual(download.call_args.args[0], 'https://image.tmdb.org/t/p/w780/example.jpg')

    def test_normalize_feed(self):
        movies = service.normalize_feed({"movies": [
            {"title": "One", "status": "Now Showing", "showtimes": "7:00 PM"},
            {"title": "Two", "status": "future"},
            {"status": "now_showing"},
        ]})
        self.assertEqual([movie["status"] for movie in movies], ["now_showing", "coming_soon"])
        self.assertEqual(movies[0]["showtimes"], ["7:00 PM"])

    def test_tmdb_match_uses_title_and_year(self):
        with mock.patch.object(service, "get_json", return_value={"results": [{"id": 42, "poster_path": "/poster.jpg"}]}) as get:
            match = service.tmdb_match({"title": "Example", "release_year": 2026}, "token", {})
        self.assertEqual(match["tmdb_id"], 42)
        self.assertEqual(get.call_args.kwargs["params"]["primary_release_year"], "2026")

    def test_no_feed_writes_fallback_catalog(self):
        with tempfile.TemporaryDirectory() as directory:
            catalog = os.path.join(directory, "catalog.json")
            with mock.patch.object(service, "CATALOG", catalog):
                service.refresh({"indy_feed_url": ""})
            with open(catalog) as handle:
                value = json.load(handle)
            self.assertGreater(len(value["movies"]), 0)

    def test_manual_roster_works_without_feed(self):
        with tempfile.TemporaryDirectory() as directory:
            catalog = os.path.join(directory, "catalog.json")
            scratch = os.path.join(directory, "scratch")
            os.mkdir(scratch)
            config = {"indy_feed_url": "", "show_qr_codes": False, "manual_movies": [{"title": "Manual Film", "release_date": "2026-09-01"}]}
            with mock.patch.object(service, "CATALOG", catalog), mock.patch.object(service, "SCRATCH", scratch):
                service.refresh(config)
            with open(catalog) as handle:
                value = json.load(handle)
            self.assertEqual(value["movies"][0]["title"], "Manual Film")

    def test_classifies_and_merges_manual_roster(self):
        api = [{"title": "Now Film", "first_show_date": "2026-09-01", "showtimes": ["7:00 PM"]}]
        manual = [
            {"title": "Tomorrow Film", "release_date": "2026-09-10"},
            {"title": "Later Film", "release_date": "2026-10-01"},
            {"title": "Now Film", "rating": "PG-13"},
        ]
        movies = service.classify_movies(api, manual, service.date(2026, 9, 9))
        self.assertEqual([movie["status"] for movie in movies], ["now_showing", "starts_tomorrow", "coming_soon"])
        self.assertEqual(movies[0]["rating"], "PG-13")
        self.assertEqual(movies[0]["showtimes"], ["7:00 PM"])

    def test_indy_xml_groups_performances(self):
        xml = b'''<schedule><show time="2026-09-11T19:00:00Z" screenName="Screen 1"><feature extId="10" title="Film" runtime="120" rating="PG"/></show><show time="2026-09-12T20:00:00Z" screenName="Screen 2"><feature extId="10" title="Film" runtime="120" rating="PG"/></show></schedule>'''
        response = BytesIO(xml)
        with mock.patch.object(service, "urlopen", return_value=response):
            with mock.patch.object(service, "venue_today", return_value=service.date(2026, 9, 11)):
                movies = service.fetch_indy_movies("https://example.test/feed.xml", 352, "America/New_York")
        self.assertEqual(len(movies), 1)
        self.assertEqual(movies[0]["first_show_date"], "2026-09-11")
        self.assertEqual(movies[0]["showtimes"], ["3:00 PM"])
        self.assertTrue(movies[0]["on_sale"])

    def test_circuit_wide_ticket_url_has_no_location(self):
        value = service.ticket_url(
            {"title": "By Any Means", "on_sale": True, "url_slug": "by-any-means"},
            {"ticket_base_url": "https://flagshipcinemas.com"},
        )
        self.assertEqual(value, "https://flagshipcinemas.com/movie/by-any-means/")


if __name__ == "__main__":
    unittest.main()
