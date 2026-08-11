# ADR 0004: Hourly feed-gated Calibre collection

**Status:** Accepted for implementation
**Date:** 2026-08-11

## Context

The Calibre experiment proved that maintained news recipes can extract useful
article bodies from a diverse publisher set. It also proved that running an
unmodified recipe every hour is unacceptable: Calibre downloads every eligible
article before the experimental SQLite importer recognizes duplicates.

The application already has a canonical Rails newsroom database, immutable
document snapshots, source-policy records, Solid Queue, and per-source
collection receipts. The experimental Python corpus is useful benchmark data,
but it must not become a second production database.

## Decision

Run news collection as part of the Rails monolith and persist it in the
canonical Rails SQLite database.

An hourly coordinator enqueues one independent job for every active source.
Each source job creates its own `CollectionRun`, exports a small read-only view
of that source's known URLs and publisher update markers, and invokes a pinned
Calibre bridge. The bridge:

1. Loads the configured Calibre recipe.
2. Runs the recipe's normal `parse_index()` or `parse_feeds()` discovery hook.
3. Normalizes and records every discovered candidate.
4. Filters the discovered candidates against the known-state file.
5. Returns only eligible candidates to Calibre's ordinary download path.
6. Emits normalized article records and a run report for Rails to import.

The wrapper preserves the original recipe's extraction behavior, including
browser configuration, print URLs, preprocessing, tag selection, and
postprocessing. It does not reimplement each publisher as a standalone
scraper.

Calibre 9.11.0 is the initial pinned runtime. Built-in recipes are loaded from
that runtime's `builtin_recipes.zip`. Project-owned recipes are committed only
when the generic recipe cannot qualify a source.

## Fetch eligibility

The first implementation has two deterministic article-fetch decisions:

- Fetch an unseen canonical URL.
- Fetch a known URL when a source declares a trustworthy update marker and the
  newly discovered marker is later than the stored `source_updated_at`.

Otherwise, record the discovery observation and do not request the article
page.

A content hash prevents duplicate snapshots after an eligible fetch. It is not
used as a justification for repeatedly downloading unchanged articles.

If a source does not expose trustworthy update metadata, it uses unseen-only
collection. Refreshing active stories may be added later as an explicit,
bounded policy with separate tests and request accounting.

## Code boundaries

```text
config/news_sources/<slug>.yml
    One source manifest: identity, recipe, discovery/update semantics,
    host allowlist, and operational limits. It may propose a source policy,
    but it cannot approve one.

app/jobs/hourly_news_collection_job.rb
    Finds active sources with approved policies and enqueues source jobs.

app/jobs/news_source_collection_job.rb
    Enforces source-scoped concurrency and invokes one collector.

app/services/collectors/calibre/
    source_registry.rb       Validates manifests and resolves recipes.
    known_state.rb           Exports the source's URL/update state.
    recipe_runner.rb         Runs the pinned bridge with timeout and receipts.
    normalizer.rb            Validates the normalized article contract.
    persister.rb             Writes documents, snapshots, and observations.
    collector.rb             Owns one source run and failure accounting.

lib/calibre_bridge/
    runner.py                Calibre entry point and filtered recipe wrapper.
    article.schema.json      Language-neutral subprocess contract.

lib/calibre_recipes/<slug>.recipe
    Optional source-specific recipe code. Most sources should not need one.

test/services/collectors/calibre/
test/jobs/
test/fixtures/files/collectors/
    Synthetic feeds, pages, and expected normalized metadata only.

tmp/source-qualification/<slug>/<run-id>/
    Ignored live output, including extracted publisher text and logs.
```

The bridge never writes application tables. Rails owns policy enforcement,
transactions, identities, immutable versions, and collection-run state. The
bridge receives a generated known-state file and returns structured results.

## Source manifests and approval

One manifest per publisher avoids merge conflicts when multiple agents qualify
sources. A manifest declares at least:

- Stable slug, display name, owner, source type, and canonical URL.
- Built-in recipe identifier or project-owned recipe path.
- Discovery endpoints and allowed article/redirect hosts.
- Whether an update field is trustworthy and which field supplies it.
- Per-run article cap, timeout, request rate, and concurrency.
- Proposed access method, terms and robots references, retention, allowed
  uses, and attribution requirements.

Adding a manifest does not activate collection. Import creates or updates a
draft source policy. A human reviews and approves the policy separately; only
an active source with a current approved policy is scheduled.

## Scheduling and isolation

Solid Queue is the production scheduler. The coordinator runs once per hour at
a fixed minute. It only fans out work; it does not collect publishers itself.

Each source job has a source-scoped concurrency key and a database-backed
hour-slot claim. Duplicate delivery of the same source/hour exits before any
network request. Different sources may run concurrently within a small global
worker limit. A failed or slow publisher cannot prevent another publisher from
finishing.

For the current Ritz evaluation, the same coordinator can be invoked manually
or by a local runner. No production schedule is enabled until the Calibre
runtime is present in the application image and the initial source policies
are approved.

## Dates and versions

Keep these meanings separate:

- `published_at`: publisher's original publication time.
- `source_updated_at`: publisher's stated update time.
- `created_at`: when The News first created the source document; operational
  evidence only, never a substitute publication date.
- snapshot `retrieved_at`: when a particular representation was requested.

The normalizer retains each raw date value, normalized UTC value, extraction
method, and confidence in document/snapshot metadata. JSON-LD
`datePublished` and `dateModified` are parsed separately. Feed `updated` is
never silently treated as publication time.

Body or title changes create a new immutable snapshot. Pure collector chrome
or whitespace changes do not. Publication-date corrections remain auditable in
snapshot metadata rather than silently erasing the earlier observation.

## Browser boundary

Camoufox is not part of the default hourly path. It may be evaluated as a
source-specific extraction engine only after a source policy permits it and a
normal browser can access the article without authentication, paywall,
challenge, or other access denial. It is not used to disguise identity or work
around a block.

## Consequences

The system gets hourly discovery without repeatedly hitting known article
pages, while retaining Calibre's maintained extraction logic. Each source is
small and independently testable. The cost is a pinned Calibre runtime and a
narrow Python subprocess boundary inside the Rails application image.

Recipes that override Calibre's complete `build_index()` or `download()` flow,
or whose discovery hook itself fetches every article, fail source qualification
until they receive an explicit adapter review.
