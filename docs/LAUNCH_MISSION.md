# The News: Launch Mission

**Status:** Locked launch direction<br>
**Brand:** The News<br>
**Promise:** Finish the news<br>
**Domain:** `finishthe.news`<br>
**Software license:** AGPL

## Why we are building The News

News has become an endless feed. There is always another update, another link,
and another reason to keep scrolling. A reader can spend hours following the
news without ever reaching a point where they feel informed or finished.

The News will publish a finite edition each day. It will contain the events a
reader needs to understand, explain them in plain language, show the evidence
behind material claims, and then end.

The central promise is simple:

> **You've finished today's news.**<br>
> The next edition arrives tomorrow.

The News is built for people who want to stay informed without giving an
unlimited amount of time and attention to the news.

## Our mission

The News gives readers a factual, finite, and dependable account of the day in
the format they prefer.

We combine editorial judgment, primary sources, evidence from responsible news
reporting, and software-assisted production. We publish original stories built
from verified claims. We do not publish summaries that substitute for another
publisher's work, and we do not hide uncertainty behind confident prose.

The official publication at `finishthe.news` will be accountable to a human
editor. The open-source software can also run autonomously for people who want
to host and configure their own publication.

## The product promise

Every edition must be:

- **Finite.** There is a deliberate end. We do not add an infinite feed below
  the edition.
- **Useful.** A reader should understand what happened, why it matters, and
  what is still unknown.
- **Restrained.** Spin is prohibited. Opinion and analysis are labeled rather
  than blended into reporting.
- **Transparent.** Material claims lead back to evidence and sources.
- **Portable.** Readers can use the web, RSS, email, PDF, or EPUB.
- **Accountable.** Corrections are visible, versioned, and carried into every
  output format.
- **Respectful.** The website has no ads, no engagement traps, and no cruft.

## What we publish

### The Top Ten

The Top Ten is the free weekday edition.

- The ten most important stories of the day.
- Approximately 10 to 15 minutes of reading.
- Published Monday through Friday.
- Available on the web, by RSS, by email, as a printable PDF, and as an EPUB.
- Includes the same evidence, sources, uncertainty disclosures, and corrections
  as the paid edition.
- Does not include the Weekend Edition.

This is not a restricted preview. It is a complete quick briefing with a clear
ending. It lets a reader experience the reporting, design, delivery formats,
and editorial judgment before paying.

### The Complete Edition

The Complete Edition is the paid weekday publication.

- One canonical daily edition.
- Approximately 45 minutes of reading, generally 8,000 to 10,000 words.
- Includes the Top Ten and the rest of the day's briefing.
- Available on the web, through a private RSS feed, by email, as a printable
  PDF, and as an EPUB.
- Includes the full archive and the Weekend Edition.
- Allows readers to remove categories they do not want.

The edition retains a common front page so that The News can exercise real
editorial judgment. Personalization removes optional sections from the
canonical edition. It does not generate a different account of reality for
every reader.

The launch price is **$10 per month or $100 per year**. New readers receive a
14-day trial of the complete product, with a reminder before the first charge.
If they do not continue, they return to The Top Ten.

### The Weekend Edition

The Weekend Edition is published on Friday evening for Saturday and Sunday
reading.

- Approximately two hours of reading, generally 20,000 to 25,000 words.
- One major cover story.
- Two or three substantial features.
- Explanatory, historical, cultural, scientific, and data-driven work.
- A short guide to the week ahead.
- Reading-time estimates for every article.

Weekend stories may use magazine-style openings and narrative structures. They
remain evidence-backed. Analysis is labeled. Opinion, if we publish it, is
separate and approved by a named human editor.

## The daily edition

The launch publication is one edition with a world section. Its expected
sections are:

1. The common front page.
2. World.
3. United States or the reader's primary country.
4. Business and economics.
5. Science and technology.
6. Health and environment.
7. Culture.
8. Sports.
9. What changed since yesterday.
10. Corrections and material updates.

Readers may remove optional categories such as sports or technology. The exact
mix can change with the news. A slow day should not be padded to fill a quota,
and an important day should not become an endless feed.

## The reporting standard

Every daily news story uses the inverted pyramid. It leads with the most
consequential confirmed information, then adds evidence, attribution, context,
and less critical detail.

Every story must answer:

1. **What happened**
2. **What is confirmed**
3. **Who says what**
4. **Why it matters**
5. **What remains uncertain**
6. **Evidence and sources**

These do not need to appear as visible headings in every story. They are the
internal reporting contract.

"Why it matters" explains demonstrable consequences and relevant context. It
is not a place for the model to invent an opinion. When causation is disputed,
we attribute the explanation to the people or evidence supporting it.

## Editorial rules

1. Prefer primary sources over articles about primary sources.
2. Clearly distinguish "X happened" from "X alleges."
3. Link the evidence behind material claims.
4. Identify what remains uncertain.
5. Label analysis and opinion rather than blending them into reporting.
6. Maintain a visible corrections history.
7. Never create a substitute rewrite of one publisher's article.
8. Credit original reporting. If a publisher broke a material fact that we
   cannot independently confirm, attribute it clearly and link to the report.
9. Use quotations only when the exact words matter. Preserve the wording and
   attribution.
10. Do not manufacture balance. Represent the evidence and material competing
    claims in proportion to their support.
11. Do not publish unsupported model inference as fact.
12. Do not silently change a published story.

The News does not promise that editorial judgment disappears. Choosing what to
cover, what to lead with, and what can be left out requires judgment. We promise
evidence-first reporting, restrained language, transparent judgment, and no
undisclosed opinion.

## From sources to stories

The News does not ask a model to rewrite an article. The production path is:

1. Collect primary sources and permitted reporting.
2. Group material that concerns the same event.
3. Extract atomic claims and attach the evidence for each claim.
4. Compare sources, dates, and conflicting accounts.
5. Mark what is confirmed, attributed, disputed, or unknown.
6. Decide whether the event belongs in the edition.
7. Draft an original story from the verified claim record.
8. Check attribution, quotations, factual support, and similarity to sources.
9. Apply the required human review.
10. Publish one approved edition to every format.

The writing stage should not receive source articles as a narrative template.
It receives claims, evidence references, attribution requirements, and approved
context. This sharply limits expressive copying, but we do not treat it as a
legal safe harbor.

## Our responsibility to sources

The News is not intended to strip value from newsrooms. Original reporting
costs money and deserves credit.

We will:

- Link to original reporting and primary evidence.
- Prefer public records, filings, transcripts, official data, direct
  statements, and other primary material.
- Use licensed feeds and APIs where required.
- Respect access controls and source-specific collection rules.
- Keep raw publisher text out of the open-source repository.
- Avoid storing full articles longer than the production process requires.
- Check published language against source language.
- Keep a source register recording access method, permissions, restrictions,
  and retention rules.
- Obtain specialist legal review before commercial publication at scale.

Geographic blocking is not a replacement for a sound source policy. We will
decide where the service can operate after reviewing the sourcing method and
applicable law.

## Software and editorial responsibility

The AGPL software is a general publishing system. It is configured out of the
box to run autonomously so that a self-hosting user can add sources, choose an
LLM provider, set a house style, and publish without an editor.

The official hosted publication uses a different operating policy. A human
editor approves every launch edition. Over time, routine low-risk reporting may
use sampled review, while high-risk subjects continue to require approval.

Mandatory human review includes politics, elections, war, crime, health,
finance, legal allegations, deaths, conflicting reports, anonymous sourcing,
and stories about private individuals. Corrections and serious accusations
receive senior review.

Open source describes the software license. It does not confer the right to use
The News name or present an independent publication as the official edition.
The project will keep the brand and official editorial identity distinct from
the AGPL code.

## The editorial desk

The human review system will be an installable Progressive Web App designed for
daily use on a laptop. It should make consequential decisions easy without
hiding the supporting evidence.

An editor must be able to:

1. Review proposed story clusters.
2. Merge, split, reject, or promote stories.
3. Read every material claim beside its evidence.
4. Resolve contradiction, freshness, and uncertainty warnings.
5. Edit a story or regenerate a selected passage.
6. Approve individual stories.
7. Review the assembled 45-minute edition.
8. Publish all formats from the approved edition.
9. Issue and propagate a correction.

The central screen is a claim-and-evidence desk, not merely a text editor. It
must flag single-source claims, close language matches, stale evidence,
unresolved contradictions, missing attribution, and high-risk subjects.

The official editorial desk requires strong authentication and an append-only
audit history. Publishing requires a live connection. The system may save
draft decisions locally, but it must not publish an uncertain offline state.

## One edition, many formats

The web, RSS, email, PDF, and EPUB outputs come from the same approved edition
record. A format renderer may change typography and navigation. It may not
rewrite the reporting.

The email is the front page of the day's edition. It contains the leading
headlines, short descriptions, total reading time, and a clear link to read.
Readers can also receive the PDF or EPUB automatically at a verified address.

Corrections update every format that can be updated. Where a delivered file or
email cannot be recalled, the next communication must identify the correction
and link to the permanent record.

## Reading experience

The website is built for reading.

- No advertising.
- No infinite scroll.
- No engagement widgets after the finish line.
- No visual clutter that competes with the reporting.
- Fast pages and minimal client-side work.
- Beautiful, highly readable type.
- A pure white reading surface in light mode.
- A carefully designed dark surface when the reader's system requests dark
  mode.
- Clear hierarchy, generous spacing, and accessible controls.
- Reading-time and edition-progress indicators that help rather than pressure
  the reader.

The design can be distinctive, but it must never make the reader work to find
the news.

## What The News is not

The News is not:

- An infinite feed.
- A collection of AI summaries.
- A substitute copy of another publisher's reporting.
- A breaking-news notification machine.
- A platform for unlabeled opinion.
- An advertising business.
- A system optimized for time on site.
- A promise that software can remove every editorial judgment.

## Launch standard

We will launch the complete product, not a web-only demonstration. Before
public release, the system must prove that it can produce:

- Ten consecutive complete weekday editions.
- Two complete Weekend Editions.
- A free Top Ten and a paid 45-minute edition on schedule.
- Human approval through the installed editorial PWA.
- Autonomous publication in a separate test instance.
- Web, RSS, email, PDF, and EPUB from one approved edition record.
- Correct reading-time budgets.
- Claim-level evidence for every material assertion.
- Visible corrections propagated across formats.
- Similarity checks against every collected source.
- A clear finish line at the end of every edition.

Reliability is part of the editorial product. A failed source, model call,
format renderer, or delivery job must fail closed rather than quietly publish
an incomplete or unreviewed edition.

## The measure that matters

The News succeeds when a reader can open one edition, understand the important
events of the day, inspect the evidence when they want to, and stop.

> **You've finished today's news.**<br>
> The next edition arrives tomorrow.
