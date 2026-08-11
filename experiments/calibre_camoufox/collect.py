#!/usr/bin/env python3
import argparse
import ast
import asyncio
import hashlib
import json
import re
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import urljoin, urlparse, urlunparse

import feedparser
import requests
from camoufox.async_api import AsyncCamoufox
from dateutil import parser as date_parser
from jsonschema import Draft202012Validator, FormatChecker
from trafilatura import extract

ROOT = Path(__file__).resolve().parents[2]
EXPERIMENT = Path(__file__).resolve().parent
RECIPE_ROOT = ROOT / "tmp" / "calibre-recipes"
OUTPUT_ROOT = ROOT / "tmp" / "calibre-camoufox"
ARTICLE_SCHEMA = json.loads((EXPERIMENT / "article.schema.json").read_text())
SOURCES = json.loads((EXPERIMENT / "sources.json").read_text())
VALIDATOR = Draft202012Validator(ARTICLE_SCHEMA, format_checker=FormatChecker())


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--articles-per-source", type=int, default=3)
    parser.add_argument("--source", action="append", dest="sources")
    return parser.parse_args()


def recipe_feeds(recipe_file):
    tree = ast.parse((RECIPE_ROOT / recipe_file).read_text())
    for node in ast.walk(tree):
        if not isinstance(node, ast.Assign):
            continue
        if not any(isinstance(target, ast.Name) and target.id == "feeds" for target in node.targets):
            continue
        try:
            value = ast.literal_eval(node.value)
        except (ValueError, TypeError):
            continue
        if isinstance(value, (list, tuple)):
            return [{"section": str(label), "url": str(url)} for label, url in value]
    return []


def normalized_url(url):
    parsed = urlparse(url)
    return urlunparse((parsed.scheme, parsed.netloc.lower(), parsed.path.rstrip("/"), "", "", ""))


def same_site(candidate, homepage):
    candidate_host = urlparse(candidate).netloc.lower().removeprefix("www.")
    homepage_host = urlparse(homepage).netloc.lower().removeprefix("www.")
    return candidate_host == homepage_host or candidate_host.endswith(f".{homepage_host}")


def likely_article_url(url, homepage):
    parsed = urlparse(url)
    path = parsed.path.rstrip("/")
    if not parsed.scheme.startswith("http") or not same_site(url, homepage):
        return False
    if len(path) < 24 or path.endswith((".jpg", ".png", ".svg", ".pdf")):
        return False
    rejected = ("/about", "/contact", "/privacy", "/terms", "/newsletters", "/podcasts", "/video")
    return not any(part in path.lower() for part in rejected)


def iso_datetime(value):
    if not value:
        return None
    try:
        parsed = date_parser.parse(value)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=UTC)
        return parsed.astimezone(UTC).isoformat()
    except (ValueError, TypeError, OverflowError):
        return None


def authors(value):
    if not value:
        return []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    return [part.strip() for part in re.split(r"\s*(?:,| and )\s*", str(value)) if part.strip()]


async def feed_candidates(source, limit):
    feeds = recipe_feeds(source["recipe"])
    feed_limit = source["discovery"].get("feed_limit", len(feeds))
    found = []
    for feed in feeds[:feed_limit]:
        try:
            response = await asyncio.to_thread(requests.get, feed["url"], timeout=30)
        except requests.RequestException:
            continue
        if response.status_code >= 400:
            continue
        parsed = feedparser.parse(response.content)
        for entry in parsed.entries:
            url = entry.get("link")
            if not url:
                continue
            found.append(
                {
                    "url": normalized_url(url),
                    "title": entry.get("title"),
                    "published_at": entry.get("published") or entry.get("updated"),
                    "description": entry.get("summary"),
                    "section": feed["section"],
                    "discovery_method": "recipe_feed",
                }
            )
    return unique_candidates(found)[:limit]


async def homepage_candidates(page, source, limit):
    url = source["discovery"]["url"]
    response = await page.goto(url, wait_until="domcontentloaded", timeout=60_000)
    if response is None:
        raise RuntimeError("homepage returned no response")
    if response.status >= 400:
        raise RuntimeError(f"homepage returned HTTP {response.status}")
    links = await page.locator("a[href]").evaluate_all(
        "els => els.map(a => ({url: a.href, title: (a.innerText || a.textContent || '').trim()}))"
    )
    found = []
    for link in links:
        candidate_url = normalized_url(urljoin(url, link["url"]))
        if not likely_article_url(candidate_url, source["homepage"]):
            continue
        found.append(
            {
                "url": candidate_url,
                "title": link["title"] or None,
                "published_at": None,
                "description": None,
                "section": None,
                "discovery_method": "recipe_homepage",
            }
        )
    candidates = unique_candidates(found)[:limit]
    if not candidates:
        raise RuntimeError("homepage contained no likely article links")
    return candidates


def unique_candidates(candidates):
    unique = {}
    for candidate in candidates:
        unique.setdefault(candidate["url"], candidate)
    return list(unique.values())


async def collect_article(page, source, candidate):
    requested_url = candidate["url"]
    retrieved_at = datetime.now(UTC).isoformat()
    response = await page.goto(requested_url, wait_until="domcontentloaded", timeout=60_000)
    status = response.status if response else 0
    if status in {401, 403, 429}:
        return None, f"explicit access response {status}"
    if status >= 400:
        return None, f"HTTP {status}"

    html = await page.content()
    extracted_json = extract(
        html,
        url=page.url,
        output_format="json",
        include_comments=False,
        include_links=False,
        include_images=False,
        with_metadata=True,
        favor_precision=True,
    )
    if not extracted_json:
        return None, "no article text extracted"
    extracted = json.loads(extracted_json)
    body = (extracted.get("text") or "").strip()
    title = (extracted.get("title") or candidate.get("title") or "").strip()
    if not title:
        return None, "no title extracted"

    warnings = []
    word_count = len(body.split())
    if word_count < 150:
        warnings.append("body_under_150_words")
    page_text = (await page.locator("body").inner_text()).lower()
    if any(marker in page_text for marker in ("subscribe to continue", "sign in to continue", "already a subscriber")):
        warnings.append("possible_access_wall")

    record = {
        "schema_version": "collected-article/v1",
        "source": {
            "slug": source["slug"],
            "name": source["name"],
            "homepage": source["homepage"],
            "recipe_file": source["recipe"],
        },
        "article": {
            "canonical_url": normalized_url(extracted.get("url") or page.url),
            "title": title,
            "authors": authors(extracted.get("author")),
            "published_at": iso_datetime(extracted.get("date") or candidate.get("published_at")),
            "updated_at": None,
            "language": extracted.get("language") or "en",
            "section": candidate.get("section"),
            "description": candidate.get("description"),
        },
        "content": {
            "body_text": body,
            "word_count": word_count,
            "content_hash": hashlib.sha256(body.encode()).hexdigest(),
        },
        "acquisition": {
            "requested_url": requested_url,
            "final_url": page.url,
            "retrieved_at": retrieved_at,
            "http_status": status,
            "collector": "camoufox",
            "discovery_method": candidate["discovery_method"],
            "warnings": warnings,
        },
    }
    errors = sorted(VALIDATOR.iter_errors(record), key=lambda error: list(error.path))
    if errors:
        return None, "; ".join(error.message for error in errors)
    return record, None


async def main():
    args = parse_args()
    selected = [source for source in SOURCES if not args.sources or source["slug"] in args.sources]
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    output_path = OUTPUT_ROOT / f"articles-{datetime.now(UTC).strftime('%Y%m%dT%H%M%SZ')}.jsonl"
    report = {"output": str(output_path), "sources": []}

    with output_path.open("w") as output:
        for source in selected:
            async with AsyncCamoufox(headless=True) as browser:
                context = await browser.new_context()
                page = await context.new_page()
                await page.route(
                    "**/*",
                    lambda route: route.abort()
                    if route.request.resource_type in {"image", "media", "font"}
                    else route.continue_(),
                )
                source_report = {"slug": source["slug"], "candidates": 0, "collected": 0, "errors": []}
                try:
                    if source["discovery"]["type"] == "recipe_feeds":
                        candidates = await feed_candidates(source, args.articles_per_source)
                    else:
                        candidates = await homepage_candidates(page, source, args.articles_per_source)
                    source_report["candidates"] = len(candidates)
                    for candidate in candidates:
                        record, error = await collect_article(page, source, candidate)
                        if error:
                            source_report["errors"].append({"url": candidate["url"], "error": error})
                            continue
                        output.write(json.dumps(record, ensure_ascii=False) + "\n")
                        output.flush()
                        source_report["collected"] += 1
                except Exception as error:  # noqa: BLE001 - isolate each experimental source
                    source_report["errors"].append({"error": f"{type(error).__name__}: {error}"})
                report["sources"].append(source_report)
                print(json.dumps(source_report), flush=True)
                await context.close()

    report_path = output_path.with_suffix(".report.json")
    report_path.write_text(json.dumps(report, indent=2))
    print(json.dumps({"output": str(output_path), "report": str(report_path)}))


if __name__ == "__main__":
    asyncio.run(main())
