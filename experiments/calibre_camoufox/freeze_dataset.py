#!/usr/bin/env python3
import argparse
import hashlib
import json
import sqlite3
from collections import Counter
from datetime import datetime, timedelta
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("database", type=Path)
    parser.add_argument("output_root", type=Path)
    parser.add_argument("--hours", type=int, default=48)
    return parser.parse_args()


def freeze(database, output_root, hours=48):
    with sqlite3.connect(database) as connection:
        connection.row_factory = sqlite3.Row
        anchor_text = connection.execute("SELECT max(last_seen_at) FROM articles").fetchone()[0]
        anchor = datetime.fromisoformat(anchor_text)
        cutoff = anchor - timedelta(hours=hours)
        rows = connection.execute(
            """
            SELECT a.*, v.id AS article_version_id, v.content_hash, v.body_text, v.word_count
            FROM articles a
            JOIN article_versions v ON v.id = (
              SELECT latest.id FROM article_versions latest
              WHERE latest.article_id = a.id ORDER BY latest.id DESC LIMIT 1
            )
            WHERE (a.published_at IS NOT NULL AND a.published_at >= ?)
               OR (a.published_at IS NULL AND a.first_seen_at >= ?)
            ORDER BY a.canonical_url
            """,
            (cutoff.isoformat(), cutoff.isoformat()),
        ).fetchall()
    dataset_id = f"clustering-{hours}h-{anchor.strftime('%Y%m%dT%H%M%SZ')}"
    dataset_root = output_root / dataset_id
    dataset_root.mkdir(parents=True, exist_ok=False)
    articles_path = dataset_root / "articles.jsonl"
    source_counts = Counter()
    unknown_dates = 0
    digest = hashlib.sha256()
    with articles_path.open("wb") as output:
        for row in rows:
            record = dict(row)
            record["authors"] = json.loads(record.pop("authors_json"))
            line = (json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n").encode()
            output.write(line)
            digest.update(line)
            source_counts[record["source_slug"]] += 1
            unknown_dates += record["published_at"] is None
    manifest = {
        "dataset_id": dataset_id,
        "database": str(database.resolve()),
        "window_hours": hours,
        "anchor": anchor.isoformat(),
        "cutoff": cutoff.isoformat(),
        "selection": "published_at within window; undated articles use first_seen_at",
        "version_policy": "latest observed content version at freeze time",
        "article_count": len(rows),
        "unknown_publication_dates": unknown_dates,
        "source_counts": dict(sorted(source_counts.items())),
        "articles_sha256": digest.hexdigest(),
        "articles_path": str(articles_path.resolve()),
    }
    manifest_path = dataset_root / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def main():
    args = parse_args()
    print(json.dumps(freeze(args.database, args.output_root, args.hours), indent=2))


if __name__ == "__main__":
    main()
