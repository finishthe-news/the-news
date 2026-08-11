#!/usr/bin/env python3
import argparse
import ast
import hashlib
import json
import os
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import urlparse, urlunparse

import feedparser
import requests
from bs4 import BeautifulSoup
from dateutil import parser as date_parser
from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[2]
EXPERIMENT = Path(__file__).resolve().parent
RECIPE_ROOT = ROOT / "tmp" / "calibre-recipes"
RUNTIME_ROOT = ROOT / "tmp" / "calibre-runtime"
CALIBRE = RUNTIME_ROOT / "app" / "ebook-convert"
CALIBRE_LIBS = RUNTIME_ROOT / "deps" / "root" / "usr" / "lib" / "x86_64-linux-gnu"
OUTPUT_ROOT = ROOT / "tmp" / "calibre-extracted"
ARTICLE_SCHEMA = json.loads((EXPERIMENT / "article.schema.json").read_text())
SOURCES = json.loads((EXPERIMENT / "sources.json").read_text())
VALIDATOR = Draft202012Validator(ARTICLE_SCHEMA, format_checker=FormatChecker())


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", action="append", dest="sources")
    parser.add_argument("--test", action="store_true", help="Ask Calibre for two feeds and two articles per feed")
    parser.add_argument("--timeout", type=int, default=900, help="Maximum seconds per publisher recipe")
    parser.add_argument("--normalize-existing", type=Path, help="Rebuild JSONL from an existing Calibre run")
    return parser.parse_args()


def normalized_url(url):
    parsed = urlparse(url)
    return urlunparse((parsed.scheme, parsed.netloc.lower(), parsed.path.rstrip("/"), "", "", ""))


def iso_datetime(value):
    if not value:
        return None
    try:
        normalized = re.sub(r"(\d{1,2})\.(\d{2})(?=\s)", r"\1:\2", str(value))
        parsed = date_parser.parse(normalized, tzinfos={"BST": 3600, "GMT": 0})
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=UTC)
        return parsed.astimezone(UTC).isoformat()
    except (ValueError, TypeError, OverflowError):
        return None


def recipe_feed_urls(recipe_path):
    tree = ast.parse(recipe_path.read_text())
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if any(isinstance(target, ast.Name) and target.id == "feeds" for target in targets):
                try:
                    feeds = ast.literal_eval(node.value)
                except (ValueError, TypeError):
                    continue
                return [item[1] for item in feeds if isinstance(item, (list, tuple)) and len(item) == 2]
    return []


def feed_dates(recipe_path):
    dates = {}
    errors = []
    headers = {"User-Agent": "The News metadata test (+https://finishthe.news)"}

    def fetch(feed_url):
        response = requests.get(feed_url, headers=headers, timeout=10)
        response.raise_for_status()
        return feedparser.parse(response.content)

    feed_urls = recipe_feed_urls(recipe_path)
    with ThreadPoolExecutor(max_workers=min(8, len(feed_urls) or 1)) as executor:
        futures = {executor.submit(fetch, feed_url): feed_url for feed_url in feed_urls}
        for future in as_completed(futures):
            feed_url = futures[future]
            try:
                parsed = future.result()
                for entry in parsed.entries:
                    url = entry.get("link")
                    date = iso_datetime(entry.get("published") or entry.get("updated"))
                    if url and date:
                        dates[normalized_url(url)] = date
            except (requests.RequestException, ValueError) as error:
                errors.append({"feed": feed_url, "error": str(error)})
    return dates, errors


def log_dates(log_path):
    if not log_path.exists():
        return {}
    text = log_path.read_text(errors="replace")
    matches = re.findall(r"https?://\S+\s+\n\s+([^\n]+)", text)
    urls = re.findall(r"(https?://\S+)\s+\n\s+[^\n]+", text)
    return {
        normalized_url(url): date
        for url, raw_date in zip(urls, matches, strict=False)
        if (date := iso_datetime(raw_date.strip()))
    }


def publication_date(soup, canonical_url, recipe_dates, logged_dates):
    for selector, attribute in (
        ("time[datetime]", "datetime"),
        ("meta[property='article:published_time']", "content"),
        ("meta[name='date']", "content"),
        ("meta[itemprop='datePublished']", "content"),
    ):
        element = soup.select_one(selector)
        if element and (date := iso_datetime(element.get(attribute))):
            return date, "article_markup", "high"
    if date := logged_dates.get(canonical_url):
        return date, "recipe_log", "high"
    if date := recipe_dates.get(canonical_url):
        return date, "recipe_feed", "high"
    dateline = soup.select_one("[data-gu-name='dateline']")
    if dateline:
        text = dateline.get_text(" ", strip=True)
        match = re.search(r"(?:First published on|Published)\s+(.+)", text, re.IGNORECASE)
        if match and (date := iso_datetime(match.group(1))):
            return date, "article_text", "medium"
    path = urlparse(canonical_url).path
    numeric = re.search(r"/(20\d{2})/(\d{2})/(\d{2})/", path)
    named = re.search(
        r"/(20\d{2})/(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)/(\d{1,2})/",
        path,
        re.IGNORECASE,
    )
    if numeric and (date := iso_datetime("-".join(numeric.groups()))):
        return date, "url_path", "medium"
    if named and (date := iso_datetime(" ".join((named.group(3), named.group(2), named.group(1))))):
        return date, "url_path", "medium"
    return None, None, None


def calibre_environment():
    environment = os.environ.copy()
    existing = environment.get("LD_LIBRARY_PATH")
    environment["LD_LIBRARY_PATH"] = f"{CALIBRE_LIBS}:{existing}" if existing else str(CALIBRE_LIBS)
    return environment


def run_recipe(source, oeb_dir, log_path, test, timeout):
    command = [
        str(CALIBRE),
        str(RECIPE_ROOT / source["recipe"]),
        str(oeb_dir),
        "--dont-download-recipe",
        "--output-profile=tablet",
    ]
    if test:
        command.append("--test")
    with log_path.open("w") as log:
        result = subprocess.run(
            command,
            env=calibre_environment(),
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
            check=False,
        )
    return result.returncode


def feed_title(article_path):
    index_path = article_path.parents[1] / "index.html"
    if not index_path.exists():
        return None
    soup = BeautifulSoup(index_path.read_text(errors="replace"), "html.parser")
    heading = soup.find(["h1", "h2"])
    return heading.get_text(" ", strip=True) if heading else None


def remove_calibre_chrome(soup):
    for element in soup.select(
        "table.touchscreen_navbar, script, style, noscript, svg, form, "
        "[aria-label='advertisement'], [aria-label='audio-module']"
    ):
        element.decompose()
    for link in soup.select("a[rel='calibre-downloaded-from']"):
        parent = link.find_parent(["p", "div"])
        if parent:
            parent.decompose()


def article_record(source, article_path, retrieved_at, recipe_dates, logged_dates):
    soup = BeautifulSoup(article_path.read_text(errors="replace"), "html.parser")
    source_link = soup.select_one("a[rel='calibre-downloaded-from']")
    if not source_link or not source_link.get("href"):
        raise ValueError("Calibre provenance URL is missing")
    canonical_url = normalized_url(source_link["href"])

    title_element = soup.find("h1") or soup.find("title")
    title = title_element.get_text(" ", strip=True) if title_element else ""
    if not title:
        raise ValueError("article title is missing")

    author_names = []
    for author in soup.select("a[rel='author']"):
        name = author.get_text(" ", strip=True)
        if name and name not in author_names:
            author_names.append(name)
    published_at, date_source, date_confidence = publication_date(
        soup, canonical_url, recipe_dates, logged_dates
    )
    language = (soup.html.get("lang") if soup.html else None) or "en"

    remove_calibre_chrome(soup)
    body = soup.find("body")
    body_text = re.sub(r"\n{3,}", "\n\n", body.get_text("\n", strip=True) if body else "").strip()
    word_count = len(body_text.split())
    warnings = []
    if word_count < 150:
        warnings.append("body_under_150_words")

    record = {
        "schema_version": "collected-article/v1",
        "source": {
            "slug": source["slug"],
            "name": source["name"],
            "homepage": source["homepage"],
            "recipe_file": source["recipe"],
        },
        "article": {
            "canonical_url": canonical_url,
            "title": title,
            "authors": author_names,
            "published_at": published_at,
            "publication_date_source": date_source,
            "publication_date_confidence": date_confidence,
            "updated_at": None,
            "language": language,
            "section": feed_title(article_path),
            "description": None,
        },
        "content": {
            "body_text": body_text,
            "word_count": word_count,
            "content_hash": hashlib.sha256(body_text.encode()).hexdigest(),
        },
        "acquisition": {
            "requested_url": canonical_url,
            "final_url": canonical_url,
            "retrieved_at": retrieved_at,
            "http_status": 200,
            "collector": "calibre",
            "discovery_method": "calibre_recipe",
            "warnings": warnings,
        },
    }
    errors = sorted(VALIDATOR.iter_errors(record), key=lambda error: list(error.path))
    if errors:
        raise ValueError("; ".join(error.message for error in errors))
    return record


def normalize_source(source, oeb_dir, log_path, output, retrieved_at):
    logged_dates = log_dates(log_path)
    article_paths = sorted(oeb_dir.glob("feed_*/article_*/index.html"))
    needs_feed_dates = False
    for article_path in article_paths:
        soup = BeautifulSoup(article_path.read_text(errors="replace"), "html.parser")
        source_link = soup.select_one("a[rel='calibre-downloaded-from']")
        if source_link and source_link.get("href"):
            canonical_url = normalized_url(source_link["href"])
            if publication_date(soup, canonical_url, {}, logged_dates)[0] is None:
                needs_feed_dates = True
                break
    if needs_feed_dates:
        recipe_dates, feed_errors = feed_dates(RECIPE_ROOT / source["recipe"])
    else:
        recipe_dates, feed_errors = {}, []
    report = {
        "slug": source["slug"],
        "calibre_articles": 0,
        "collected": 0,
        "dated": 0,
        "feed_metadata_errors": feed_errors,
        "errors": [],
    }
    report["calibre_articles"] = len(article_paths)
    for article_path in article_paths:
        try:
            record = article_record(source, article_path, retrieved_at, recipe_dates, logged_dates)
            output.write(json.dumps(record, ensure_ascii=False) + "\n")
            output.flush()
            report["collected"] += 1
            if record["article"]["published_at"]:
                report["dated"] += 1
        except (OSError, ValueError) as error:
            report["errors"].append({"path": str(article_path), "error": str(error)})
    return report


def main():
    args = parse_args()
    selected = [source for source in SOURCES if not args.sources or source["slug"] in args.sources]
    run_id = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    run_root = args.normalize_existing.resolve() if args.normalize_existing else OUTPUT_ROOT / run_id
    run_root.mkdir(parents=True, exist_ok=True)
    output_path = run_root / "articles.jsonl"
    report = {"run_id": run_id, "test_mode": args.test, "output": str(output_path), "sources": []}

    with output_path.open("w") as output:
        for source in selected:
            oeb_dir = run_root / f"{source['slug']}-oeb"
            log_path = run_root / f"{source['slug']}.log"
            source_report = {"slug": source["slug"], "calibre_articles": 0, "collected": 0, "errors": []}
            try:
                return_code = 0 if args.normalize_existing else run_recipe(
                    source, oeb_dir, log_path, args.test, args.timeout
                )
                if return_code:
                    source_report["errors"].append({"error": f"Calibre exited with status {return_code}"})
                elif oeb_dir.exists():
                    source_report = normalize_source(
                        source, oeb_dir, log_path, output, datetime.now(UTC).isoformat()
                    )
            except subprocess.TimeoutExpired:
                source_report["errors"].append({"error": f"Calibre exceeded {args.timeout} seconds"})
            report["sources"].append(source_report)
            print(json.dumps(source_report), flush=True)

    report_path = run_root / "report.json"
    report_path.write_text(json.dumps(report, indent=2))
    print(json.dumps({"output": str(output_path), "report": str(report_path)}))


if __name__ == "__main__":
    main()
