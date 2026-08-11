# Ten-source collection results

Run date: 2026-08-10

## Final panel

1. Associated Press
2. BBC
3. The Guardian
4. NPR
5. CBC
6. ABC News Australia
7. Deutsche Welle
8. Al Jazeera English
9. USA Today
10. NBC News

## Calibre recipe run

The actual Calibre recipes were run without the collector imposing an article
cap. The ignored local output is
`tmp/calibre-extracted/20260810T123227Z/articles.jsonl`.

### Aggregate result

- 653 collected records from 10 publishers
- 606 unique canonical URLs (47 duplicate appearances across feed sections)
- 0 JSON Schema validation errors
- 771-word median extracted body
- 0-word minimum and 5,574-word maximum
- 33 records under the 150-word completeness warning threshold
- 505 records without a retained publication date
- 498 records without a retained author
- 0 recipe failures and 0 article normalization failures

| Publisher | Records |
|---|---:|
| Associated Press | 22 |
| BBC | 102 |
| The Guardian | 186 |
| NPR | 10 |
| CBC | 135 |
| ABC News Australia | 122 |
| Deutsche Welle | 29 |
| Al Jazeera English | 25 |
| USA Today | 7 |
| NBC News | 15 |

Calibre successfully performs source-specific retrieval and body extraction.
It does not produce a clean ingestion set by itself: recipes can include the
same article in multiple sections, video/player/cartoon entries can contain
little text, and many recipe outputs omit author and publication-time
metadata. Those records are retained and flagged rather than silently removed.

## Date recovery and repeat-run result

The saved first run was normalized again without revisiting article pages.
Dates were recovered from article markup, recipe logs, recipe RSS feeds,
retained datelines, and dated canonical paths. This improved date coverage
from 148 of 653 feed appearances to 509 of 653. After URL deduplication, 487 of
606 unique articles had a publication date.

CBC remains the main date gap: its nine RSS endpoints timed out from Ritz even
though Calibre article extraction succeeded. CBC articles retain a distinct
`first_seen_at`; that observation is not relabeled as publication time.

A second full Calibre run produced 650 appearances from nine successful
publishers. USA Today returned HTTP 403 at its homepage and was not retried or
bypassed. SQLite ingestion classified the second run as:

- 27 new canonical URLs
- 598 unchanged appearances
- 25 existing articles with new content hashes
- 633 total unique articles and 658 immutable content versions
- 1,303 total run/source/section observations

The frozen 48-hour clustering dataset contains 552 latest article versions
from all ten publishers. It includes 120 articles with unknown publication
dates selected by first-seen time and flags that limitation in its manifest.

## First clustering experiment

The frozen dataset was embedded locally with the pinned
`BAAI/bge-small-en-v1.5` ONNX model using the complete title plus the first 350
normalized body words. Average-linkage agglomerative clustering was run with
cosine distance at two declared thresholds.

| Distance threshold | Proposed clusters | Grouped articles | Multi-source clusters | Singletons |
|---:|---:|---:|---:|---:|
| 0.145 | 53 | 146 | 42 | 406 |
| 0.200 | 72 | 207 | 53 | 345 |

The stricter run produced strong multi-publisher same-episode groups such as
the Nizhnekamsk drone strike, Typhoon Dolphin, the FIFA governance dispute,
and the Thailand shooting. It still made at least two obvious mistakes during
the initial manual audit: two unrelated CBC mRNA-vaccine stories merged, and
an NPR roundup joined the specific art-school abuse article included in that
roundup.

The 0.200 run visibly overmerged broad topics. Examples include joining a
Russian strike on Kyiv with the Ukrainian strike inside Russia, adding a
separate Infantino affair to the FIFA governance dispute, and broadening
wildfire and temperature coverage beyond one episode. It remains useful as a
missed-merge review view, not as the preferred partition.

Two independent executions produced the same cluster-membership projection
SHA-256: `60f0b3b9cc5340065f3f47960c51c5b499ce2a005deb5312e9f029ad9ba0b96d`.
No cluster is accepted or persisted by this experiment.

After manual review, the 0.145 partition was accepted as the experimental
baseline. Its occasional false joins remain visible to later model review; the
0.200 partition remains a diagnostic missed-merge view only.

## Deterministic local dossiers and scoring control

`EditorialRanking::LocalClusterDossier` now converts a local cluster into a
bounded scoring dossier without model judgment. It removes article bodies
under 150 words, chooses at most one representative per publisher by average
within-cluster similarity, and caps evidence at six publishers. A substantial
singleton is admitted rather than suppressed by a publisher-count rule.

Three deliberately different candidates were scored with the same anchored
rubric and strict JSON schema using `openai/gpt-5.4-mini`:

| Candidate | Evidence | Scores: consequence / audience / reach / public interest / novelty | Input tokens | Cost |
| --- | ---: | --- | ---: | ---: |
| Nizhnekamsk drone-strike cluster | 6 of 7 publishers | 4 / 3 / 3 / 4 / 2 | 5,779 | $0.00516675 |
| Birthright-citizenship singleton | 1 publisher | 4 / 4 / 3 / 5 / 3 | 2,460 | $0.00251100 |
| Edinburgh comedy-review singleton | 1 publisher | 0 / 1 / 2 / 1 / 1 | 1,972 | $0.00201000 |

The result is directionally useful: the important singleton was not lost, and
the routine review received low scores. It also demonstrates that sending full
article bodies for every first-pass candidate will be too expensive at the
expected 50-source scale. Compact preliminary scoring remains the next design
question; full dossiers are suitable for a much smaller promoted set.

The frozen corpus is retained as the reproducible benchmark. A future fresh
collection should begin at a recorded 2:00 AM `America/New_York` cutoff and be
frozen separately to validate authoritative publication dates, explicit
first-seen fallback, and cutoff-to-cutoff selection. It must not replace this
benchmark.

## Earlier generic browser run

Before running the recipes directly, the first spike used recipe URLs only as
discovery hints, then rendered article pages with Camoufox and extracted them
with Trafilatura. That historical sample contains 30 records at
`tmp/calibre-camoufox/ten-source-sample-20260810.jsonl`; it is not the current
Calibre collector.

## Initial sources replaced after live testing

- Reuters: its homepage returned HTTP 401 in Camoufox.
- Politico: its RSS document exists, but Cloudflare challenged the Python feed
  client and Firefox treated the RSS response as a download.
- Ars Technica: feed discovery worked, but all three article pages returned
  HTTP 403.

The collector did not retry around those access responses.

## What the combined spikes established

- Calibre recipes can directly retrieve and extract complete publisher
  editions when executed by Calibre.
- Calibre and Camoufox are separate engines; a Calibre recipe cannot simply be
  run "through" Camoufox.
- Each recipe failure is isolated within its publisher and logged separately.
- Successful extraction does not guarantee editorial relevance. The sample
  includes newsletters, shopping coverage, celebrity coverage, culture, and
  sports that will need deterministic article-type and section filters before
  clustering.
