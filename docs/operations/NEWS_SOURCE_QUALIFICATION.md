# News source qualification

**Status:** Required integration contract
**Date:** 2026-08-11

Every publisher is integrated and reviewed independently. An agent may add one
source manifest and the minimum source-specific extraction code required for
that source. It must not redesign the shared collector, approve a source
policy, enable a production schedule, or hide an access failure.

## Agent assignment

Give an agent exactly one publisher and this contract:

1. Inspect the official feed, current Calibre recipe if one exists, terms,
   robots file, redirects, and article hosts.
2. Add `config/news_sources/<slug>.yml` with a draft policy proposal and bounded
   operational settings.
3. Use the generic recipe path first. Add
   `lib/calibre_recipes/<slug>.recipe` only when live evidence shows that the
   generic path cannot produce clean substantial bodies.
4. Add only synthetic publisher-shaped fixtures and deterministic tests.
5. Run the source's isolated live qualification twice at low rate.
6. Return the manifest, tests, ignored report path, metrics, access findings,
   and any limitation requiring editorial review.

## Deterministic acceptance gates

### Registration and policy

- The source slug is unique.
- Owner, canonical URL, access method, feed endpoints, terms URL, robots URL,
  retention, allowed uses, attribution, request rate, and concurrency are
  declared.
- Missing, draft, expired, or retired policy records prevent collection.
- The integration does not mark its own policy approved.

### Discovery and identity

- Initial discovery creates one candidate per canonical article URL.
- Tracking parameters normalize away; article-defining query parameters do
  not.
- Feed, requested, redirected, and canonical aliases remain traceable.
- Article and redirect hosts remain inside the manifest allowlist.
- A hard candidate/article cap and process timeout are enforced.

### No-repeat requests

Using a recording fake HTTP surface:

- The first run requests a new article exactly once.
- An unchanged second run requests discovery but zero article pages.
- One new URL causes exactly one new article request.
- A newer trusted publisher update marker makes one known URL eligible.
- Untrusted or absent update metadata does not cause a repeat fetch.

### Dates and content versions

- JSON-LD `datePublished` and `dateModified` populate separate fields.
- Feed `published` and `updated` remain distinct.
- Raw value, normalized UTC value, method, and confidence are retained.
- A missing publication time remains null; first-seen time is not substituted.
- A body or title correction creates exactly one new immutable snapshot.
- Identical normalized content and collector-chrome-only changes create no new
  snapshot.
- Earlier snapshots remain readable and linked to their collection runs.

### Jobs and failure isolation

- Double-enqueuing one source/hour performs at most one network collection.
- A still-running source does not overlap its next hourly run.
- Different publishers can proceed independently.
- One malformed article does not discard valid articles from the same run.
- One publisher's 403, 429, timeout, or extraction failure does not prevent
  another publisher from succeeding.
- Errors are bounded and contain no secrets, cookies, or authorization data.
- An explicit block is reported and is not retried with another identity.

## Live qualification

Live qualification is opt-in and never substitutes for deterministic tests.
Run only the named publisher, then repeat the run to exercise the no-repeat
gate. Store full output only beneath:

```text
tmp/source-qualification/<slug>/<run-id>/
```

The report must include:

- Discovered, eligible, fetched, normalized, and deduplicated counts.
- Article requests made on the first and second runs.
- Unique canonical URLs and unexpected redirect hosts.
- Minimum, median, and maximum body words.
- Counts and percentages at or above 150 and 300 words.
- Published-date, updated-date, and author coverage.
- 403, 429, timeout, paywall, login, challenge, and malformed-body counts.
- Total requests, elapsed time, recipe/runtime version, and warnings.

Pass requires at least one current schema-valid article, no access-control
bypass, no unexpected host, and zero unchanged article-page requests on the
second run. A source with successful extraction but poor body/date coverage is
reported for review rather than silently accepted.

## Fixture boundary

Commit only synthetic prose and the smallest DOM or feed shape needed to
exercise the source. Do not commit captured publisher article bodies.

Shared fixture shapes belong under:

```text
test/fixtures/files/collectors/shared/
```

Source-specific synthetic shapes belong under:

```text
test/fixtures/files/collectors/<slug>/
```

The ignored live report may be summarized in the handoff, but article text and
raw response bodies stay out of Git.

## Initial US-focused qualification queue

The first candidates combine current public feeds with useful coverage gaps:

1. ABC News
2. CBS News
3. PBS NewsHour
4. Texas Tribune
5. CalMatters
6. The Marshall Project
7. Roll Call
8. Christian Science Monitor

Christian Science Monitor already has a Calibre built-in recipe. The other
eight should begin with the generic RSS recipe path. Semafor is a later
candidate with a strict recency and entry cap because its main feed is large.
STAT and TIME require additional free-versus-metered access checks. The Hill
and The 19th are deferred because live article requests returned HTTP 403.
