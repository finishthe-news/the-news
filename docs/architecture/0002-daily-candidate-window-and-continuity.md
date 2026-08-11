# ADR 0002: Daily candidate window and story continuity

**Status:** Accepted<br>
**Date:** 2026-08-11

## Context

The weekday edition is published for a general United States audience at
5:00 AM Eastern time. Collection will eventually cover at least 50 publishers,
so each edition needs a precise evidence window that neither loses overnight
articles nor repeatedly treats unchanged stories as new candidates.

Stories also develop across editions. A strict one-day partition would discard
useful context, while repeatedly rescoring every old cluster would create cost
and volume without adding editorial signal.

## Decision

Use `America/New_York` for editorial cutoffs and store the corresponding UTC
instants with each edition run.

- Tuesday through Friday editions use articles first observed after the prior
  edition's 2:00 AM cutoff and through the current day's 2:00 AM cutoff.
- Monday editions use Friday 2:00 AM through Monday 2:00 AM.
- Weekday publication remains 5:00 AM, leaving three hours for clustering,
  scoring, selection, writing, verification, and human review.
- An article with an authoritative publication time is eligible when that time
  falls inside the window. When publication time is unavailable, first-seen
  time is the explicit fallback; it is never relabeled as publication time.
- Newly eligible articles are compared with both new candidates and active
  clusters from prior editions. New evidence may extend an existing story.
- An unchanged prior cluster is not rescored merely because it remains active.
  A changed cluster is rescored with its new evidence and retained prior
  context.
- Prior published stories provide continuity and context, but they do not
  replace current source evidence.
- Singletons with a substantial article body remain scoring candidates. A
  minimum publisher count must not suppress consequential exclusive or early
  reporting.

The weekend edition is a separate process and is not governed by this daily
candidate window.

## Consequences

Each run must persist its timezone, cutoff instants, prior-edition reference,
and whether every article qualified by publication time or first-seen fallback.
Cluster identity must survive across edition runs so new evidence can attach
without duplicating the story. Ranking must still control the large candidate
set produced by singletons; clustering alone is not a relevance filter.

The existing frozen 48-hour corpus remains a reproducible clustering benchmark.
A fresh collection beginning at a recorded cutoff will be frozen separately to
validate publication-date provenance, first-seen fallback, and daily-window
selection without overwriting the benchmark.
