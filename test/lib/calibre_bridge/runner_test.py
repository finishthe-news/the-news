import json
import os
import tempfile
import threading
import time
import unittest
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from lib.calibre_bridge import runner


class Feed(list):
    pass


class Article:
    def __init__(self, url, title, updated=None):
        self.url = url
        self.title = title
        self.updated = updated


class DiscoveryFilterTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.decisions = Path(self.temporary.name) / "decisions.jsonl"

    def tearDown(self):
        self.temporary.cleanup()

    def build_filter(self, *, trust=False, cap=100):
        return runner.DiscoveryFilter(
            source_slug="example",
            known_documents=[
                {
                    "canonical_url": "https://example.com/known?utm_source=x",
                    "source_updated_at": "2026-08-11T01:00:00Z",
                }
            ],
            decisions_path=self.decisions,
            trust_update_markers=trust,
            article_cap=cap,
            allowed_hosts=["example.com"],
        )

    def records(self):
        return [json.loads(line) for line in self.decisions.read_text().splitlines()]

    def test_parse_index_filters_known_and_preserves_article_query(self):
        discovery = self.build_filter()
        feeds = [
            (
                "News",
                [
                    {"title": "Known", "url": "https://EXAMPLE.com/known/?utm_medium=rss"},
                    {"title": "New", "url": "https://example.com/story?id=7&utm_source=rss"},
                ],
            )
        ]

        result = discovery.filter_feeds(feeds, "parse_index")

        self.assertEqual([item["title"] for item in result[0][1]], ["New"])
        self.assertEqual(self.records()[0]["reason"], "known_unchanged")
        self.assertEqual(self.records()[1]["canonical_url"], "https://example.com/story?id=7")

    def test_parse_feeds_mutates_feed_object_without_replacing_it(self):
        discovery = self.build_filter()
        feed = Feed([Article("https://example.com/known", "Known"), Article("https://example.com/new", "New")])

        result = discovery.filter_feeds([feed], "parse_feeds")

        self.assertIs(result[0], feed)
        self.assertEqual([article.title for article in feed], ["New"])

    def test_only_trusted_newer_marker_refetches_known_url(self):
        untrusted = self.build_filter(trust=False)
        article = {"url": "https://example.com/known", "updated": "2026-08-11T02:00:00Z"}
        self.assertFalse(untrusted.decide(article, "parse_index"))

        trusted_decisions = Path(self.temporary.name) / "trusted.jsonl"
        trusted = runner.DiscoveryFilter(
            source_slug="example",
            known_documents=[{"canonical_url": "https://example.com/known", "source_updated_at": "2026-08-11T01:00:00Z"}],
            decisions_path=trusted_decisions,
            trust_update_markers=True,
            article_cap=100,
            allowed_hosts=["example.com"],
        )
        self.assertTrue(trusted.decide(article, "parse_index"))

    def test_struct_time_feed_dates_are_emitted_as_rfc3339(self):
        discovery = self.build_filter()
        article = {
            "url": "https://example.com/new",
            "title": "New",
            "date": time.struct_time((2026, 8, 10, 17, 51, 0, 0, 222, 0)),
        }

        self.assertTrue(discovery.decide(article, "parse_feeds"))

        self.assertEqual(self.records()[0]["feed_published"], "2026-08-10T17:51:00Z")

    def test_trusted_struct_time_update_marker_is_compared_as_rfc3339(self):
        decisions = Path(self.temporary.name) / "struct-time-update.jsonl"
        discovery = runner.DiscoveryFilter(
            source_slug="example",
            known_documents=[
                {
                    "canonical_url": "https://example.com/known",
                    "source_updated_at": "2026-08-11T01:00:00Z",
                }
            ],
            decisions_path=decisions,
            trust_update_markers=True,
            article_cap=100,
            allowed_hosts=["example.com"],
        )
        article = {
            "url": "https://example.com/known",
            "updated": time.struct_time((2026, 8, 11, 2, 0, 0, 1, 223, 0)),
        }

        self.assertTrue(discovery.decide(article, "parse_feeds"))

        record = json.loads(decisions.read_text().strip())
        self.assertEqual(record["source_updated_at"], "2026-08-11T02:00:00Z")
        self.assertEqual(record["reason"], "trusted_newer_update")

    def test_article_cap_is_global_across_feeds(self):
        discovery = self.build_filter(cap=1)
        feeds = [
            ("One", [{"url": "https://example.com/a", "title": "A"}]),
            ("Two", [{"url": "https://example.com/b", "title": "B"}]),
        ]

        result = discovery.filter_feeds(feeds, "parse_index")

        self.assertEqual(len(result[0][1]), 1)
        self.assertEqual(len(result[1][1]), 0)
        self.assertEqual(self.records()[1]["reason"], "article_cap")

    def test_disallowed_host_is_recorded_without_fetching(self):
        discovery = self.build_filter()

        self.assertFalse(discovery.decide({"url": "https://other.test/story"}, "parse_feeds"))

        self.assertEqual(self.records()[0]["reason"], "disallowed_host")

    def test_duplicate_url_is_eligible_only_once_across_feeds(self):
        discovery = self.build_filter()
        feeds = [
            ("One", [{"url": "https://example.com/new?utm_source=one", "title": "New"}]),
            ("Two", [{"url": "https://example.com/new?utm_source=two", "title": "New again"}]),
        ]

        result = discovery.filter_feeds(feeds, "parse_index")

        self.assertEqual(len(result[0][1]), 1)
        self.assertEqual(len(result[1][1]), 0)
        self.assertEqual(self.records()[1]["reason"], "duplicate_in_run")


class BridgeContractTest(unittest.TestCase):
    def test_known_state_rejects_invalid_update_marker(self):
        with self.assertRaisesRegex(ValueError, "source_updated_at"):
            runner.validate_known_state(
                {
                    "schema_version": runner.KNOWN_STATE_VERSION,
                    "source_slug": "example",
                    "documents": [{"canonical_url": "https://example.com/a", "source_updated_at": "yesterday"}],
                }
            )

    def test_extract_article_hashes_title_and_body_and_keeps_body_under_run_dir(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            article_dir = root / "oeb" / "feed_0" / "article_0"
            article_dir.mkdir(parents=True)
            (article_dir / "index.html").write_text(
                """<html><head><title>Fallback</title>
                <meta property="article:published_time" content="2026-08-11T01:00:00Z"></head>
                <body><a rel="calibre-downloaded-from" href="https://example.com/story?utm_source=rss">Source</a>
                <h1>Useful title</h1><p>First paragraph.</p><script>ignore me</script><p>Second paragraph.</p></body></html>"""
            )
            run_dir = root / "run"

            records = runner.extract_articles(root / "oeb", run_dir, "example", Path("example.recipe"))

            self.assertEqual(len(records), 1)
            record = records[0]
            self.assertEqual(record["canonical_url"], "https://example.com/story")
            self.assertEqual(record["title"], "Useful title")
            body_path = Path(record["body_text_path"])
            self.assertIn(run_dir.resolve(), body_path.parents)
            self.assertNotIn("ignore me", body_path.read_text())
            expected = runner.hashlib.sha256(f"Useful title\n{body_path.read_text().strip()}".encode()).hexdigest()
            self.assertEqual(record["content_hash"], expected)

    def test_extract_article_joins_raw_feed_dates_from_discovery(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            article_dir = root / "oeb" / "feed_0" / "article_0"
            article_dir.mkdir(parents=True)
            (article_dir / "index.html").write_text(
                "<html><body><a rel='calibre-downloaded-from' href='https://example.com/story'>Source</a>"
                "<h1>Title</h1><p>Body</p></body></html>"
            )
            decisions = [{
                "canonical_url": "https://example.com/story",
                "discovered_url": "https://example.com/story?utm_source=feed",
                "decision": "fetch",
                "feed_published": "Tue, 11 Aug 2026 01:00:00 GMT",
                "feed_updated": "2026-08-11T02:00:00Z",
            }]

            record = runner.extract_articles(
                root / "oeb", root / "run", "example", Path("example.recipe"), decisions
            )[0]

            self.assertEqual(record["dates"]["feed_published"], "Tue, 11 Aug 2026 01:00:00 GMT")
            self.assertEqual(record["dates"]["feed_updated"], "2026-08-11T02:00:00Z")
            self.assertEqual(record["requested_url"], "https://example.com/story?utm_source=feed")

    def test_wrapped_recipe_installs_hook_after_original_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            recipe = root / "source.recipe"
            destination = root / "wrapped.recipe"
            recipe.write_text("class Example: pass\n")

            runner.build_wrapped_recipe(recipe, destination)

            text = destination.read_text()
            self.assertLess(text.index("class Example"), text.index("_the_news_install(globals())"))

    def test_recipe_mode_accepts_manifest_feed_overrides(self):
        arguments = runner.parse_args([
            "--recipe", "example.recipe",
            "--feed", "https://example.com/us.xml",
            "--known-state", "known.json",
            "--output-dir", "output",
            "--run-dir", "run",
        ])

        self.assertEqual(arguments.feed, ["https://example.com/us.xml"])

    def test_generic_recipe_uses_only_supplied_name_and_feeds(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / "generic.recipe"

            runner.build_generic_recipe(
                "Example News",
                ["https://example.com/news.xml", "https://example.com/politics.xml"],
                destination,
            )

            text = destination.read_text()
            self.assertIn("title = 'Example News'", text)
            self.assertIn("https://example.com/news.xml", text)
            self.assertIn("https://example.com/politics.xml", text)
            self.assertTrue(text.rstrip().endswith("_the_news_install(globals())"))

    def test_generic_recipe_requires_a_feed(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(ValueError, "at least one feed"):
                runner.build_generic_recipe("Example News", [], Path(temporary) / "generic.recipe")

    def test_extracts_one_builtin_recipe_from_the_pinned_runtime(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            calibre_bin = root / "calibre" / "ebook-convert"
            recipes = calibre_bin.parent / "resources" / "builtin_recipes.zip"
            recipes.parent.mkdir(parents=True)
            calibre_bin.write_text("")
            with zipfile.ZipFile(recipes, "w") as archive:
                archive.writestr("example.recipe", "class Example: pass\n")
            destination = root / "example.recipe"

            runner.extract_builtin_recipe(calibre_bin, "example.recipe", destination)

            self.assertEqual(destination.read_text(), "class Example: pass\n")

    def test_rejects_unsafe_or_missing_builtin_recipe(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            calibre_bin = root / "calibre" / "ebook-convert"
            recipes = calibre_bin.parent / "resources" / "builtin_recipes.zip"
            recipes.parent.mkdir(parents=True)
            calibre_bin.write_text("")
            with zipfile.ZipFile(recipes, "w"):
                pass

            with self.assertRaisesRegex(ValueError, "filename"):
                runner.extract_builtin_recipe(calibre_bin, "../example.recipe", root / "out")
            with self.assertRaisesRegex(ValueError, "does not exist"):
                runner.extract_builtin_recipe(calibre_bin, "example.recipe", root / "out")


class SyntheticPublisherHandler(BaseHTTPRequestHandler):
    article_requests = 0

    def do_GET(self):
        if self.path == "/feed.xml":
            port = self.server.server_address[1]
            body = f"""<?xml version="1.0"?><rss version="2.0"><channel>
              <title>Example News</title><link>http://127.0.0.1:{port}/</link>
              <item><title>Synthetic report</title><link>http://127.0.0.1:{port}/story</link>
              <pubDate>Tue, 11 Aug 2026 01:00:00 GMT</pubDate></item>
            </channel></rss>""".encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/rss+xml")
        elif self.path == "/story":
            type(self).article_requests += 1
            words = " ".join(f"word{i}" for i in range(180))
            body = f"""<html><head><title>Synthetic report</title>
              <meta property="article:published_time" content="2026-08-11T01:00:00Z"></head>
              <body><h1>Synthetic report</h1><p>{words}</p></body></html>""".encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
        else:
            body = b"not found"
            self.send_response(404)
            self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format, *_args):
        return


class RealCalibreSyntheticTest(unittest.TestCase):
    calibre = Path(os.environ.get("CALIBRE_BIN", "tmp/calibre-runtime/app/ebook-convert"))

    @unittest.skipUnless(calibre.exists(), "pinned Calibre runtime is not installed")
    def test_second_run_discovers_but_does_not_request_known_article(self):
        SyntheticPublisherHandler.article_requests = 0
        server = ThreadingHTTPServer(("127.0.0.1", 0), SyntheticPublisherHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                feed = f"http://127.0.0.1:{server.server_address[1]}/feed.xml"
                first_state = root / "first-state.json"
                first_state.write_text(json.dumps({
                    "schema_version": runner.KNOWN_STATE_VERSION,
                    "source_slug": "example",
                    "documents": [],
                }))
                first_run = root / "first"
                first_exit = runner.run([
                    "--source-name", "Example News", "--feed", feed,
                    "--known-state", str(first_state),
                    "--output-dir", str(first_run / "oeb"),
                    "--run-dir", str(first_run),
                    "--calibre-bin", str(self.calibre),
                    "--concurrency-cap", "1",
                    "--article-host", "127.0.0.1",
                ])
                self.assertEqual(first_exit, 0, (first_run / "calibre.log").read_text())
                self.assertEqual(SyntheticPublisherHandler.article_requests, 1)
                article = json.loads((first_run / "articles.jsonl").read_text().strip())
                self.assertIsNotNone(article["dates"]["feed_published"])

                second_state = root / "second-state.json"
                second_state.write_text(json.dumps({
                    "schema_version": runner.KNOWN_STATE_VERSION,
                    "source_slug": "example",
                    "documents": [{"canonical_url": article["canonical_url"], "source_updated_at": None}],
                }))
                second_run = root / "second"
                second_exit = runner.run([
                    "--source-name", "Example News", "--feed", feed,
                    "--known-state", str(second_state),
                    "--output-dir", str(second_run / "oeb"),
                    "--run-dir", str(second_run),
                    "--calibre-bin", str(self.calibre),
                    "--concurrency-cap", "1",
                    "--article-host", "127.0.0.1",
                ])

                self.assertEqual(second_exit, 0)
                self.assertEqual(SyntheticPublisherHandler.article_requests, 1)
                report = json.loads((second_run / "run-report.json").read_text())
                self.assertEqual(report["outcome"], "no_changes")
                self.assertEqual(report["counts"]["eligible"], 0)
        finally:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    unittest.main()
