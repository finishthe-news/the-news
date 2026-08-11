#!/usr/bin/env python3
import argparse
import json
import sqlite3
from datetime import UTC, datetime
from pathlib import Path

SCHEMA = """
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS collection_runs (
  id TEXT PRIMARY KEY,
  input_path TEXT NOT NULL,
  imported_at TEXT NOT NULL,
  record_count INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS articles (
  id INTEGER PRIMARY KEY,
  canonical_url TEXT NOT NULL UNIQUE,
  source_slug TEXT NOT NULL,
  source_name TEXT NOT NULL,
  title TEXT NOT NULL,
  authors_json TEXT NOT NULL,
  published_at TEXT,
  publication_date_source TEXT,
  publication_date_confidence TEXT,
  language TEXT NOT NULL,
  first_seen_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS article_versions (
  id INTEGER PRIMARY KEY,
  article_id INTEGER NOT NULL REFERENCES articles(id),
  content_hash TEXT NOT NULL,
  body_text TEXT NOT NULL,
  word_count INTEGER NOT NULL,
  title TEXT NOT NULL,
  first_seen_at TEXT NOT NULL,
  UNIQUE(article_id, content_hash)
);

CREATE TABLE IF NOT EXISTS article_observations (
  id INTEGER PRIMARY KEY,
  collection_run_id TEXT NOT NULL REFERENCES collection_runs(id),
  article_id INTEGER NOT NULL REFERENCES articles(id),
  content_hash TEXT NOT NULL,
  section TEXT NOT NULL DEFAULT '',
  retrieved_at TEXT NOT NULL,
  warnings_json TEXT NOT NULL,
  UNIQUE(collection_run_id, article_id, content_hash, section)
);
"""


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("database", type=Path)
    parser.add_argument("jsonl", type=Path)
    parser.add_argument("--run-id")
    return parser.parse_args()


def prefer_date(existing, candidate):
    if not candidate:
        return existing
    if not existing or existing[2] != "high" or candidate[2] == "high":
        return candidate
    return existing


def ingest(database, jsonl, run_id=None):
    with jsonl.open() as input_file:
        rows = [json.loads(line) for line in input_file]
    run_id = run_id or jsonl.parent.name
    imported_at = datetime.now(UTC).isoformat()
    result = {
        "run_id": run_id,
        "records": len(rows),
        "new_articles": 0,
        "new_versions": 0,
        "unchanged_records": 0,
        "new_observations": 0,
        "already_imported": False,
    }
    database.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(database) as connection:
        connection.executescript(SCHEMA)
        if connection.execute("SELECT 1 FROM collection_runs WHERE id = ?", (run_id,)).fetchone():
            result["already_imported"] = True
            return result
        connection.execute(
            "INSERT INTO collection_runs(id, input_path, imported_at, record_count) VALUES (?, ?, ?, ?)",
            (run_id, str(jsonl.resolve()), imported_at, len(rows)),
        )
        for row in rows:
            article = row["article"]
            content = row["content"]
            acquisition = row["acquisition"]
            url = article["canonical_url"]
            existing = connection.execute(
                "SELECT id, published_at, publication_date_source, publication_date_confidence "
                "FROM articles WHERE canonical_url = ?",
                (url,),
            ).fetchone()
            candidate_date = (
                article.get("published_at"),
                article.get("publication_date_source"),
                article.get("publication_date_confidence"),
            )
            if existing:
                article_id = existing[0]
                chosen_date = prefer_date(existing[1:4], candidate_date)
                connection.execute(
                    "UPDATE articles SET title = ?, authors_json = ?, published_at = ?, "
                    "publication_date_source = ?, publication_date_confidence = ?, last_seen_at = ? WHERE id = ?",
                    (
                        article["title"],
                        json.dumps(article.get("authors", []), ensure_ascii=False),
                        *chosen_date,
                        acquisition["retrieved_at"],
                        article_id,
                    ),
                )
            else:
                cursor = connection.execute(
                    "INSERT INTO articles(canonical_url, source_slug, source_name, title, authors_json, "
                    "published_at, publication_date_source, publication_date_confidence, language, "
                    "first_seen_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        url,
                        row["source"]["slug"],
                        row["source"]["name"],
                        article["title"],
                        json.dumps(article.get("authors", []), ensure_ascii=False),
                        *candidate_date,
                        article["language"],
                        acquisition["retrieved_at"],
                        acquisition["retrieved_at"],
                    ),
                )
                article_id = cursor.lastrowid
                result["new_articles"] += 1
            version = connection.execute(
                "INSERT OR IGNORE INTO article_versions(article_id, content_hash, body_text, word_count, title, first_seen_at) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (
                    article_id,
                    content["content_hash"],
                    content["body_text"],
                    content["word_count"],
                    article["title"],
                    acquisition["retrieved_at"],
                ),
            )
            if version.rowcount:
                result["new_versions"] += 1
            else:
                result["unchanged_records"] += 1
            observation = connection.execute(
                "INSERT OR IGNORE INTO article_observations(collection_run_id, article_id, content_hash, section, "
                "retrieved_at, warnings_json) VALUES (?, ?, ?, ?, ?, ?)",
                (
                    run_id,
                    article_id,
                    content["content_hash"],
                    article.get("section") or "",
                    acquisition["retrieved_at"],
                    json.dumps(acquisition["warnings"]),
                ),
            )
            result["new_observations"] += observation.rowcount
    return result


def main():
    args = parse_args()
    print(json.dumps(ingest(args.database, args.jsonl, args.run_id), indent=2))


if __name__ == "__main__":
    main()
