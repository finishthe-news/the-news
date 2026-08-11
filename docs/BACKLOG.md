# The News backlog

This is the working list of accepted limitations and deferred improvements.
Items belong here when they should not block the current experiment but must
remain visible before production launch.

## Collection and source management

- [ ] **Detect updates to previously collected articles.** The initial hourly
  collector intentionally uses unseen-URL-only fetching when a feed has no
  trustworthy per-article update timestamp. This avoids repeatedly downloading
  known pages, but it can miss corrections or expansions made at the same URL.
  Add, in order:
  1. feed-item fingerprints over URL, title, description, and date metadata;
  2. immediate refetching for genuine per-article update timestamps;
  3. conditional HTTP checks using `ETag` and `Last-Modified` during an
     article's first 48 hours; and
  4. a bounded refresh policy for active stories when no validator exists.
  Do not represent feed-level build times or copied publication dates as
  article-update signals.

- [ ] Capture exact HTTP status, final redirect, `ETag`, and `Last-Modified`
  receipts from Calibre article requests.

- [ ] Extract and preserve publisher author/byline metadata.

- [ ] Add source-specific body cleanup for PBS NewsHour and The Marshall
  Project before either source is eligible for production.

- [ ] Qualify additional US-focused sources individually, beginning with Texas
  Tribune, CalMatters, Roll Call, and CBS News.

- [ ] Revisit raw-content retention after measuring the private burn-in. Source
  policies currently declare a 90-day retention target, but Robert explicitly
  deferred automatic deletion while we determine whether longer evidence
  storage is operationally useful.

## Hourly operation

- [ ] Connect the Calibre bridge to Rails with one source-scoped collector that
  creates and closes `CollectionRun` receipts.

- [ ] Add the hourly coordinator and per-source Solid Queue jobs using leased
  `NewsCollectionSlot` claims for deduplication and crash recovery.

- [ ] Package the pinned Calibre runtime in the application image and verify it
  under the same non-root user as the worker.

- [ ] Add an approved source-registration workflow; manifests may propose only
  draft policies and must never self-approve.

- [ ] Run a bounded local soak test before enabling the production schedule:
  at least 24 hours, no overlapping source runs, no duplicate article fetches,
  and visible failure receipts.

## Editorial pipeline

- [ ] Revisit economical preliminary scoring after the live hourly corpus is
  large enough to represent a real edition window.

- [ ] Build claim extraction, contradiction review, original drafting, and
  publication gates after source collection and clustering are stable.
