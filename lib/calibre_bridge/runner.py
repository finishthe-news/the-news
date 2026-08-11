#!/usr/bin/env python3
"""Run a Calibre recipe after filtering discovery against Rails-known state.

The module is intentionally usable by both ordinary Python (the coordinator)
and Calibre's bundled Python (the injected recipe hooks). It never opens the
Rails database.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import re
import subprocess
import sys
import time
import zipfile
from datetime import UTC, datetime
from html.parser import HTMLParser
from pathlib import Path
from typing import Any
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit


TRACKING_PARAMETERS = {
    "fbclid",
    "gclid",
    "mc_cid",
    "mc_eid",
    "ref",
}
KNOWN_STATE_VERSION = "calibre-known-state/v1"
DECISION_VERSION = "calibre-discovery-decision/v1"
ARTICLE_VERSION = "calibre-article/v1"
REPORT_VERSION = "calibre-run-report/v1"

_FILTER_STATE: "DiscoveryFilter | None" = None


def canonicalize_url(value: str | None) -> str | None:
    """Normalize identity without dropping article-defining query fields."""
    if not value or not isinstance(value, str):
        return None
    try:
        parsed = urlsplit(value.strip())
        if parsed.scheme.lower() not in {"http", "https"} or not parsed.hostname:
            return None
        host = parsed.hostname.lower()
        port = parsed.port
        if port and not ((parsed.scheme.lower() == "http" and port == 80) or (parsed.scheme.lower() == "https" and port == 443)):
            host = f"{host}:{port}"
        query = [
            (key, item)
            for key, item in parse_qsl(parsed.query, keep_blank_values=True)
            if not key.lower().startswith("utm_") and key.lower() not in TRACKING_PARAMETERS
        ]
        path = re.sub(r"/{2,}", "/", parsed.path or "/")
        if path != "/":
            path = path.rstrip("/")
        return urlunsplit((parsed.scheme.lower(), host, path, urlencode(sorted(query)), ""))
    except (TypeError, ValueError):
        return None


def url_host(value: str | None) -> str | None:
    try:
        return urlsplit(value or "").hostname
    except (TypeError, ValueError):
        return None


def normalize_datetime(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, time.struct_time):
        parsed = datetime(*value[:6], tzinfo=UTC)
    elif isinstance(value, datetime):
        parsed = value
    else:
        text = str(value).strip()
        if not text:
            return None
        try:
            parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
        except ValueError:
            return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _article_value(article: Any, name: str) -> Any:
    if isinstance(article, dict):
        return article.get(name)
    return getattr(article, name, None)


def _article_url(article: Any) -> str | None:
    return _article_value(article, "url") or _article_value(article, "link")


def _updated_marker(article: Any) -> str | None:
    for field in ("source_updated_at", "updated_at", "updated"):
        if marker := normalize_datetime(_article_value(article, field)):
            return marker
    return None


def _raw_marker(article: Any, fields: tuple[str, ...]) -> str | None:
    for field in fields:
        value = _article_value(article, field)
        if value is not None:
            if isinstance(value, time.struct_time):
                return datetime(*value[:6], tzinfo=UTC).isoformat().replace("+00:00", "Z")
            return value.isoformat() if isinstance(value, datetime) else str(value)
    return None


class DiscoveryFilter:
    def __init__(
        self,
        *,
        source_slug: str,
        known_documents: list[dict[str, Any]],
        decisions_path: Path,
        trust_update_markers: bool,
        article_cap: int,
        allowed_hosts: list[str],
    ) -> None:
        self.source_slug = source_slug
        self.known = {
            canonical: normalize_datetime(document.get("source_updated_at"))
            for document in known_documents
            if (canonical := canonicalize_url(document.get("canonical_url")))
        }
        self.decisions_path = decisions_path
        self.trust_update_markers = trust_update_markers
        self.article_cap = article_cap
        self.allowed_hosts = frozenset(allowed_hosts)
        self.eligible_count = 0
        self.seen_this_run: set[str] = set()

    def decide(self, article: Any, hook: str) -> bool:
        discovered_url = _article_url(article)
        canonical_url = canonicalize_url(discovered_url)
        feed_published = _raw_marker(article, ("published", "published_at", "date"))
        feed_updated = _raw_marker(article, ("updated", "updated_at", "source_updated_at"))
        discovered_updated = _updated_marker(article)
        known_updated = self.known.get(canonical_url) if canonical_url else None

        if canonical_url is None:
            fetch, reason = False, "invalid_url"
        elif url_host(canonical_url) not in self.allowed_hosts:
            fetch, reason = False, "disallowed_host"
        elif canonical_url in self.seen_this_run:
            fetch, reason = False, "duplicate_in_run"
        elif canonical_url not in self.known:
            fetch, reason = True, "unseen"
        elif (
            self.trust_update_markers
            and discovered_updated
            and (known_updated is None or discovered_updated > known_updated)
        ):
            fetch, reason = True, "trusted_newer_update"
        else:
            fetch, reason = False, "known_unchanged"

        if fetch and self.eligible_count >= self.article_cap:
            fetch, reason = False, "article_cap"
        if fetch:
            self.eligible_count += 1
        if canonical_url:
            self.seen_this_run.add(canonical_url)

        self._emit(
            {
                "schema_version": DECISION_VERSION,
                "source_slug": self.source_slug,
                "hook": hook,
                "discovered_url": discovered_url,
                "canonical_url": canonical_url,
                "title": _article_value(article, "title"),
                "feed_published": feed_published,
                "feed_updated": feed_updated,
                "source_updated_at": discovered_updated,
                "known_source_updated_at": known_updated,
                "decision": "fetch" if fetch else "skip",
                "reason": reason,
            }
        )
        return fetch

    def filter_feeds(self, feeds: Any, hook: str) -> Any:
        """Filter both parse_index tuples and Calibre Feed list objects."""
        if feeds is None:
            return None
        filtered_feeds = []
        for feed in feeds:
            if isinstance(feed, tuple) and len(feed) == 2:
                title, articles = feed
                filtered_feeds.append((title, [article for article in articles if self.decide(article, hook)]))
                continue
            articles = list(feed)
            kept = [article for article in articles if self.decide(article, hook)]
            if hasattr(feed, "remove_article"):
                for article in articles:
                    if article not in kept:
                        feed.remove_article(article)
                filtered_feeds.append(feed)
                continue
            try:
                feed[:] = kept
                filtered_feeds.append(feed)
            except (TypeError, AttributeError):
                filtered_feeds.append(kept)
        return filtered_feeds

    def _emit(self, record: dict[str, Any]) -> None:
        self.decisions_path.parent.mkdir(parents=True, exist_ok=True)
        with self.decisions_path.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")


def _filter_from_environment() -> DiscoveryFilter:
    global _FILTER_STATE
    if _FILTER_STATE is not None:
        return _FILTER_STATE
    known_state_path = Path(os.environ["THE_NEWS_KNOWN_STATE"])
    known_state = json.loads(known_state_path.read_text(encoding="utf-8"))
    validate_known_state(known_state)
    _FILTER_STATE = DiscoveryFilter(
        source_slug=known_state["source_slug"],
        known_documents=known_state["documents"],
        decisions_path=Path(os.environ["THE_NEWS_DECISIONS"]),
        trust_update_markers=os.environ.get("THE_NEWS_TRUST_UPDATES") == "1",
        article_cap=int(os.environ["THE_NEWS_ARTICLE_CAP"]),
        allowed_hosts=json.loads(os.environ["THE_NEWS_ALLOWED_HOSTS"]),
    )
    return _FILTER_STATE


def install_recipe_wrappers(namespace: dict[str, Any]) -> None:
    """Patch recipe discovery hooks before BasicNewsRecipe schedules pages."""
    try:
        from calibre.web.feeds.news import BasicNewsRecipe
    except ImportError as error:  # pragma: no cover - only called by Calibre
        raise RuntimeError("recipe wrappers require Calibre's Python runtime") from error

    concurrency_cap = int(os.environ["THE_NEWS_CONCURRENCY_CAP"])
    requests_per_minute = int(os.environ["THE_NEWS_REQUESTS_PER_MINUTE"])
    configured_feed_urls = json.loads(os.environ.get("THE_NEWS_FEEDS", "[]"))
    recipe_classes = [
        value
        for value in namespace.values()
        if isinstance(value, type)
        and value is not BasicNewsRecipe
        and issubclass(value, BasicNewsRecipe)
        and value.__module__ == namespace.get("__name__", "builtins")
    ]
    for recipe_class in recipe_classes:
        if configured_feed_urls:
            recipe_class.feeds = [
                (f"Feed {position}", feed_url)
                for position, feed_url in enumerate(configured_feed_urls, start=1)
            ]
        original_parse_index = recipe_class.parse_index
        original_parse_feeds = recipe_class.parse_feeds

        def parse_index(self: Any, _original: Any = original_parse_index) -> Any:
            return _filter_from_environment().filter_feeds(_original(self), "parse_index")

        def parse_feeds(self: Any, _original: Any = original_parse_feeds) -> Any:
            return _filter_from_environment().filter_feeds(_original(self), "parse_feeds")

        recipe_class.parse_index = parse_index
        recipe_class.parse_feeds = parse_feeds
        configured = int(getattr(recipe_class, "simultaneous_downloads", concurrency_cap))
        recipe_class.simultaneous_downloads = min(configured, concurrency_cap)
        minimum_delay = 60.0 * recipe_class.simultaneous_downloads / requests_per_minute
        recipe_class.delay = max(float(getattr(recipe_class, "delay", 0)), minimum_delay)


def extract_builtin_recipe(calibre_bin: Path, recipe_id: str, destination: Path) -> None:
    """Extract one pinned built-in recipe without copying the recipe corpus."""
    if not re.fullmatch(r"[a-z0-9][a-z0-9_.-]*\.recipe", recipe_id):
        raise ValueError("builtin recipe id must be a .recipe filename")
    archive = calibre_bin.resolve().parent / "resources" / "builtin_recipes.zip"
    if not archive.is_file():
        raise ValueError(f"Calibre built-in recipe archive does not exist: {archive}")
    try:
        with zipfile.ZipFile(archive) as recipes:
            destination.write_bytes(recipes.read(recipe_id))
    except KeyError as error:
        raise ValueError(f"Calibre built-in recipe does not exist: {recipe_id}") from error


def validate_known_state(document: dict[str, Any]) -> None:
    if document.get("schema_version") != KNOWN_STATE_VERSION:
        raise ValueError(f"known state must use {KNOWN_STATE_VERSION}")
    if not isinstance(document.get("source_slug"), str) or not document["source_slug"]:
        raise ValueError("known state requires source_slug")
    if not isinstance(document.get("documents"), list):
        raise ValueError("known state requires a documents array")
    for item in document["documents"]:
        if not isinstance(item, dict) or not canonicalize_url(item.get("canonical_url")):
            raise ValueError("each known document requires an HTTP(S) canonical_url")
        if item.get("source_updated_at") is not None and not normalize_datetime(item["source_updated_at"]):
            raise ValueError("source_updated_at must be null or an ISO 8601 timestamp")


class ArticleHTMLParser(HTMLParser):
    SKIPPED = {"script", "style", "noscript", "svg", "form"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.skip_depth = 0
        self.in_title = False
        self.in_h1 = False
        self.title_parts: list[str] = []
        self.h1_parts: list[str] = []
        self.text_parts: list[str] = []
        self.canonical_url: str | None = None
        self.authors: list[str] = []
        self.dates: dict[str, str | None] = {
            "feed_published": None,
            "feed_updated": None,
            "article_published": None,
            "article_updated": None,
        }

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag in self.SKIPPED:
            self.skip_depth += 1
        if self.skip_depth:
            return
        self.in_title = self.in_title or tag == "title"
        self.in_h1 = self.in_h1 or tag == "h1"
        rel = (values.get("rel") or "").split()
        if tag == "a" and "calibre-downloaded-from" in rel:
            self.canonical_url = values.get("href")
        if tag == "meta":
            key = values.get("property") or values.get("name") or values.get("itemprop")
            if key in {"article:published_time", "datePublished"}:
                self.dates["article_published"] = values.get("content")
            elif key in {"article:modified_time", "dateModified"}:
                self.dates["article_updated"] = values.get("content")

    def handle_endtag(self, tag: str) -> None:
        if tag in self.SKIPPED and self.skip_depth:
            self.skip_depth -= 1
            return
        if self.skip_depth:
            return
        if tag == "title":
            self.in_title = False
        elif tag == "h1":
            self.in_h1 = False
        elif tag in {"p", "div", "li", "h1", "h2", "h3", "blockquote", "br"}:
            self.text_parts.append("\n")

    def handle_data(self, data: str) -> None:
        if self.skip_depth:
            return
        value = html.unescape(data).strip()
        if not value:
            return
        self.text_parts.append(value)
        if self.in_title:
            self.title_parts.append(value)
        if self.in_h1:
            self.h1_parts.append(value)


def extract_articles(
    output_dir: Path,
    run_dir: Path,
    source_slug: str,
    recipe_path: Path,
    decisions: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    articles = []
    discovery_by_url = {
        item["canonical_url"]: item
        for item in decisions or []
        if item.get("canonical_url") and item.get("decision") == "fetch"
    }
    body_root = (run_dir / "articles").resolve()
    body_root.mkdir(parents=True, exist_ok=True)
    retrieved_at = datetime.now(UTC).isoformat().replace("+00:00", "Z")
    for index_path in sorted(output_dir.glob("feed_*/article_*/index.html")):
        parser = ArticleHTMLParser()
        parser.feed(index_path.read_text(encoding="utf-8", errors="replace"))
        canonical_url = canonicalize_url(parser.canonical_url)
        if canonical_url is None:
            continue
        discovery = discovery_by_url.get(canonical_url, {})
        title = " ".join(parser.h1_parts or parser.title_parts).strip()
        body_text = re.sub(r"[ \t]+", " ", " ".join(parser.text_parts))
        body_text = re.sub(r"\s*\n\s*", "\n", body_text).strip()
        identity = hashlib.sha256(canonical_url.encode("utf-8")).hexdigest()[:20]
        body_path = (body_root / f"{identity}.txt").resolve()
        if body_root not in body_path.parents:
            raise ValueError("article body path escaped run directory")
        body_path.write_text(body_text, encoding="utf-8")
        content_hash = hashlib.sha256(f"{title.strip()}\n{body_text.strip()}".encode("utf-8")).hexdigest()
        articles.append(
            {
                "schema_version": ARTICLE_VERSION,
                "source_slug": source_slug,
                "canonical_url": canonical_url,
                "requested_url": discovery.get("discovered_url") or canonical_url,
                "title": title,
                "authors": parser.authors,
                "language": "en",
                "section": None,
                "description": None,
                "dates": {
                    **parser.dates,
                    "feed_published": discovery.get("feed_published"),
                    "feed_updated": discovery.get("feed_updated"),
                },
                "body_text_path": str(body_path),
                "word_count": len(body_text.split()),
                "content_hash": content_hash,
                "acquisition": {
                    "retrieved_at": retrieved_at,
                    "collector": "calibre",
                    "recipe_path": str(recipe_path),
                },
            }
        )
    return articles


def _write_jsonl(path: Path, records: list[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8") as stream:
        for record in records:
            stream.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")


def build_wrapped_recipe(recipe_path: Path, destination: Path) -> None:
    source = recipe_path.read_text(encoding="utf-8")
    repository_root = str(Path(__file__).resolve().parents[2])
    source += f"\n\nimport sys\nsys.path.insert(0, {repository_root!r})\n"
    source += "from lib.calibre_bridge.runner import install_recipe_wrappers as _the_news_install\n"
    source += "_the_news_install(globals())\n"
    destination.write_text(source, encoding="utf-8")


def build_generic_recipe(source_name: str, feed_urls: list[str], destination: Path) -> None:
    if not source_name.strip():
        raise ValueError("generic recipes require a source name")
    if not feed_urls:
        raise ValueError("generic recipes require at least one feed URL")
    feeds = []
    for position, feed_url in enumerate(feed_urls, start=1):
        if canonicalize_url(feed_url) is None:
            raise ValueError(f"generic feed {position} must be an HTTP(S) URL")
        feeds.append((f"Feed {position}", feed_url))
    repository_root = str(Path(__file__).resolve().parents[2])
    source = (
        "from calibre.web.feeds.news import BasicNewsRecipe\n\n"
        "class TheNewsGenericRecipe(BasicNewsRecipe):\n"
        f"    title = {source_name!r}\n"
        "    language = 'en'\n"
        "    oldest_article = 3\n"
        "    max_articles_per_feed = 100\n"
        f"    feeds = {feeds!r}\n\n"
        f"import sys\nsys.path.insert(0, {repository_root!r})\n"
        "from lib.calibre_bridge.runner import install_recipe_wrappers as _the_news_install\n"
        "_the_news_install(globals())\n"
    )
    destination.write_text(source, encoding="utf-8")


def calibre_environment(calibre_bin: Path, base: dict[str, str] | None = None) -> dict[str, str]:
    environment = dict(base or os.environ)
    runtime_root = calibre_bin.resolve().parents[1]
    library_root = runtime_root / "deps" / "root" / "usr" / "lib"
    library_dirs = [path for path in library_root.glob("*-linux-gnu") if path.is_dir()]
    existing = environment.get("LD_LIBRARY_PATH")
    values = [str(path) for path in sorted(library_dirs)]
    if existing:
        values.append(existing)
    if values:
        environment["LD_LIBRARY_PATH"] = os.pathsep.join(values)
    return environment


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--recipe", type=Path)
    source.add_argument("--builtin-recipe")
    source.add_argument("--source-name")
    parser.add_argument("--feed", action="append", default=[])
    parser.add_argument("--article-host", action="append", default=[])
    parser.add_argument("--redirect-host", action="append", default=[])
    parser.add_argument("--known-state", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--calibre-bin", type=Path, default=Path("ebook-convert"))
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--article-cap", type=int, default=100)
    parser.add_argument("--concurrency-cap", type=int, default=4)
    parser.add_argument("--requests-per-minute", type=int, default=10)
    parser.add_argument("--trust-update-markers", action="store_true")
    return parser.parse_args(argv)


def run(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    for name in ("timeout", "article_cap", "concurrency_cap", "requests_per_minute"):
        if getattr(args, name) <= 0:
            raise ValueError(f"{name.replace('_', '-')} must be positive")
    known_state = json.loads(args.known_state.read_text(encoding="utf-8"))
    validate_known_state(known_state)
    allowed_hosts = args.article_host + args.redirect_host
    if not args.article_host:
        raise ValueError("at least one --article-host is required")
    run_dir = args.run_dir.resolve()
    output_dir = args.output_dir.resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)
    decisions_path = run_dir / "discovery-decisions.jsonl"
    articles_path = run_dir / "articles.jsonl"
    report_path = run_dir / "run-report.json"
    wrapped_recipe = run_dir / "wrapped.recipe"
    log_path = run_dir / "calibre.log"
    if args.recipe:
        build_wrapped_recipe(args.recipe, wrapped_recipe)
        recipe_reference = str(args.recipe)
    elif args.builtin_recipe:
        builtin_recipe = run_dir / "builtin.recipe"
        extract_builtin_recipe(args.calibre_bin, args.builtin_recipe, builtin_recipe)
        build_wrapped_recipe(builtin_recipe, wrapped_recipe)
        recipe_reference = f"builtin:{args.builtin_recipe}"
    else:
        build_generic_recipe(args.source_name, args.feed, wrapped_recipe)
        recipe_reference = "generated:generic"
    decisions_path.write_text("", encoding="utf-8")

    environment = calibre_environment(args.calibre_bin)
    repository_root = Path(__file__).resolve().parents[2]
    environment["PYTHONPATH"] = os.pathsep.join(filter(None, [str(repository_root), environment.get("PYTHONPATH")]))
    environment.update(
        {
            "THE_NEWS_KNOWN_STATE": str(args.known_state.resolve()),
            "THE_NEWS_DECISIONS": str(decisions_path),
            "THE_NEWS_TRUST_UPDATES": "1" if args.trust_update_markers else "0",
            "THE_NEWS_ARTICLE_CAP": str(args.article_cap),
            "THE_NEWS_CONCURRENCY_CAP": str(args.concurrency_cap),
            "THE_NEWS_REQUESTS_PER_MINUTE": str(args.requests_per_minute),
            "THE_NEWS_FEEDS": json.dumps(args.feed),
            "THE_NEWS_ALLOWED_HOSTS": json.dumps(allowed_hosts),
        }
    )
    command = [
        str(args.calibre_bin),
        str(wrapped_recipe),
        str(output_dir),
        "--dont-download-recipe",
        "--output-profile=tablet",
    ]
    started = datetime.now(UTC)
    timed_out = False
    with log_path.open("w", encoding="utf-8") as log:
        try:
            completed = subprocess.run(
                command,
                env=environment,
                stdout=log,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=args.timeout,
                check=False,
            )
            exit_code = completed.returncode
        except subprocess.TimeoutExpired:
            timed_out = True
            exit_code = 124
    finished = datetime.now(UTC)

    decisions = [json.loads(line) for line in decisions_path.read_text(encoding="utf-8").splitlines() if line]
    eligible_count = sum(item["decision"] == "fetch" for item in decisions)
    calibre_exit_code = exit_code
    if exit_code == 0 and decisions and eligible_count == 0:
        outcome = "no_changes"
    elif exit_code == 0:
        outcome = "succeeded"
    elif not timed_out and decisions and eligible_count == 0:
        # BasicNewsRecipe treats an intentionally empty filtered feed as an
        # error. For the bridge, this is the expected unchanged-run result.
        outcome = "no_changes"
        exit_code = 0
    else:
        outcome = "failed"
    articles = (
        extract_articles(
            output_dir,
            run_dir,
            known_state["source_slug"],
            Path(recipe_reference),
            decisions,
        )
        if outcome == "succeeded"
        else []
    )
    _write_jsonl(articles_path, articles)
    report = {
        "schema_version": REPORT_VERSION,
        "source_slug": known_state["source_slug"],
        "started_at": started.isoformat().replace("+00:00", "Z"),
        "finished_at": finished.isoformat().replace("+00:00", "Z"),
        "elapsed_seconds": round((finished - started).total_seconds(), 6),
        "exit_code": exit_code,
        "calibre_exit_code": calibre_exit_code,
        "outcome": outcome,
        "timed_out": timed_out,
        "counts": {
            "discovered": len(decisions),
            "eligible": eligible_count,
            "skipped": sum(item["decision"] == "skip" for item in decisions),
            "normalized": len(articles),
        },
        "files": {
            "articles": str(articles_path),
            "decisions": str(decisions_path),
            "log": str(log_path),
            "output_dir": str(output_dir),
        },
        "instrumentation": {
            "http_statuses": False,
            "final_redirects": False,
            "note": "Calibre does not expose per-request HTTP statuses or final redirect headers through this bridge.",
        },
    }
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return exit_code


def main() -> None:
    try:
        raise SystemExit(run())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"calibre bridge: {error}", file=sys.stderr)
        raise SystemExit(2) from error


if __name__ == "__main__":
    main()
