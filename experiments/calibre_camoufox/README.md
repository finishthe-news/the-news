# Calibre recipe collection spike

This experiment runs maintained Calibre news recipes and normalizes their
article output into one JSON schema.

- Calibre recipes are copied into `tmp/calibre-recipes/` and remain outside
  Git.
- The pinned Calibre runtime lives in `tmp/calibre-runtime/` and remains
  outside Git.
- `ebook-convert` owns feed retrieval and source-specific article extraction.
- `collect_calibre.py` converts Calibre's OEB article files into
  `collected-article/v1` JSON records.
- Full article output is written below `tmp/calibre-extracted/` and remains
  outside Git.

Camoufox is not part of this path. It remains an independently testable
fallback for a publisher whose Calibre recipe cannot retrieve an otherwise
permitted public article. The collectors do not log in, solve challenges,
rotate proxies, or retry explicit access denials.

Run all ten recipes without an article cap:

```bash
uv sync --project experiments/calibre_camoufox
uv run --project experiments/calibre_camoufox \
  experiments/calibre_camoufox/collect_calibre.py
```

Run one recipe in Calibre's small test mode:

```bash
uv run --project experiments/calibre_camoufox \
  experiments/calibre_camoufox/collect_calibre.py --source npr --test
```

`--source` can be repeated. Each recipe has a 15-minute timeout by default;
override it with `--timeout SECONDS`.

Import a run into the idempotent SQLite corpus:

```bash
uv run --project experiments/calibre_camoufox \
  experiments/calibre_camoufox/corpus.py \
  tmp/news-corpus.sqlite3 tmp/calibre-extracted/RUN_ID/articles.jsonl
```

The corpus stores one article per canonical URL, immutable versions by content
hash, and every source/section observation. Reimporting the same run is a
no-op. A changed body creates a new version instead of overwriting the old
one.

Freeze a deterministic 48-hour clustering input:

```bash
uv run --project experiments/calibre_camoufox \
  experiments/calibre_camoufox/freeze_dataset.py \
  tmp/news-corpus.sqlite3 tmp/clustering-datasets --hours 48
```

Publication dates retain their recovery source and confidence. The order is
article markup, Calibre recipe log, recipe RSS metadata, retained dateline
text, and dated canonical URL. Missing publication dates remain null;
`first_seen_at` is stored separately and is never represented as a confirmed
publication time.

Running an unmodified Calibre recipe again can re-request every eligible
article even when SQLite later recognizes an unchanged hash. Recurring
collection therefore still needs a feed-first new-or-updated URL gate before
it is scheduled hourly or every two hours.
