import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

import numpy as np
from bs4 import BeautifulSoup
from cluster_experiment import cluster_labels, normalized_text
from collect_calibre import publication_date
from corpus import ingest


class PublicationDateTest(unittest.TestCase):
    def test_prefers_structured_article_markup(self):
        soup = BeautifulSoup('<time datetime="2026-08-10T09:37:43Z">Today</time>', "html.parser")
        self.assertEqual(
            publication_date(soup, "https://example.com/story", {}, {}),
            ("2026-08-10T09:37:43+00:00", "article_markup", "high"),
        )

    def test_uses_feed_date_when_markup_is_missing(self):
        soup = BeautifulSoup("<article>Story</article>", "html.parser")
        url = "https://example.com/story"
        self.assertEqual(
            publication_date(soup, url, {url: "2026-08-10T08:00:00+00:00"}, {}),
            ("2026-08-10T08:00:00+00:00", "recipe_feed", "high"),
        )

    def test_parses_guardian_dateline_as_medium_confidence(self):
        soup = BeautifulSoup(
            '<div data-gu-name="dateline">First published on Mon 10 Aug 2026 12.54 BST</div>',
            "html.parser",
        )
        date, source, confidence = publication_date(soup, "https://example.com/story", {}, {})
        self.assertEqual((source, confidence), ("article_text", "medium"))
        self.assertTrue(date.startswith("2026-08-10T"))

    def test_recovers_date_from_dated_url_path(self):
        soup = BeautifulSoup("<article>Story</article>", "html.parser")
        date, source, confidence = publication_date(
            soup, "https://example.com/world/2026/aug/09/story", {}, {}
        )
        self.assertEqual((date, source, confidence), ("2026-08-09T00:00:00+00:00", "url_path", "medium"))


class CorpusTest(unittest.TestCase):
    def record(self, body="body one", retrieved_at="2026-08-10T10:00:00+00:00"):
        import hashlib

        return {
            "source": {"slug": "test", "name": "Test"},
            "article": {
                "canonical_url": "https://example.com/story",
                "title": "Story",
                "authors": [],
                "published_at": "2026-08-10T09:00:00+00:00",
                "publication_date_source": "recipe_feed",
                "publication_date_confidence": "high",
                "language": "en",
                "section": "News",
            },
            "content": {
                "body_text": body,
                "word_count": len(body.split()),
                "content_hash": hashlib.sha256(body.encode()).hexdigest(),
            },
            "acquisition": {"retrieved_at": retrieved_at, "warnings": []},
        }

    def test_repeated_runs_keep_one_article_and_add_changed_version(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database = root / "corpus.sqlite3"
            first = root / "first.jsonl"
            first.write_text(json.dumps(self.record()) + "\n")
            second = root / "second.jsonl"
            second.write_text(json.dumps(self.record("body two", "2026-08-10T12:00:00+00:00")) + "\n")
            self.assertEqual(ingest(database, first, "first")["new_articles"], 1)
            self.assertEqual(ingest(database, second, "second")["new_versions"], 1)
            with sqlite3.connect(database) as connection:
                self.assertEqual(connection.execute("SELECT count(*) FROM articles").fetchone()[0], 1)
                self.assertEqual(connection.execute("SELECT count(*) FROM article_versions").fetchone()[0], 2)
                self.assertEqual(connection.execute("SELECT count(*) FROM article_observations").fetchone()[0], 2)


class ClusteringExperimentTest(unittest.TestCase):
    def test_text_contract_uses_title_and_first_350_body_words(self):
        article = {"title": "  A   title  ", "body_text": " ".join(f"word-{i}" for i in range(400))}
        text = normalized_text(article)
        self.assertTrue(text.startswith("A title\n\nword-0"))
        self.assertEqual(len(text.split()) - 2, 350)
        self.assertNotIn("word-350", text)

    def test_average_linkage_separates_distant_vectors(self):
        vectors = np.asarray([[1.0, 0.0], [0.99, 0.01], [0.0, 1.0]])
        vectors = vectors / np.linalg.norm(vectors, axis=1, keepdims=True)
        labels = cluster_labels(vectors, 0.05)
        self.assertEqual(labels[0], labels[1])
        self.assertNotEqual(labels[0], labels[2])


if __name__ == "__main__":
    unittest.main()
