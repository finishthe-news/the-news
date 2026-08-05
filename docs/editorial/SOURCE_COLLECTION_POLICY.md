# Source Collection Policy

**Status:** Initial operating policy<br>
**Date:** 2026-08-04

## Purpose

The News collects public primary sources and permitted reporting so it can
identify events, extract claims, compare evidence, and write original news
stories. Collection must be honest, inspectable, gentle on source systems, and
consistent with the editorial and copyright boundaries in the launch mission.

Public access does not justify hiding who we are, evading technical controls,
or placing unreasonable load on another service. It also does not require The
News to pretend that public facts are unavailable for reporting. Each source
gets an explicit policy rather than an unrecorded assumption.

## Collector identity

Every HTTP collector sends a truthful user agent identifying The News and the
public project URL. Production collectors also provide a monitored contact
address.

The default form is:

```text
TheNews/<version> (+https://finishthe.news; mailto:<collector-contact>)
```

Do not impersonate a browser, search engine, person, or other organization. Do
not rotate identities to avoid a limit or block.

## Access rules

- Collect only material available without bypassing authentication, paywalls,
  CAPTCHAs, access controls, or deliberate technical blocks unless a license
  explicitly permits that access.
- Prefer documented APIs, feeds, bulk data, and primary documents over HTML
  scraping when they provide the required evidence.
- Read and record published API terms, rate limits, licenses, and source
  notices before enabling a source in production.
- Retrieve and record `robots.txt` for web collectors. A conflicting rule
  requires an explicit source-policy review. Do not silently ignore it.
- Honor `Retry-After`, HTTP rate-limit responses, and source-specific limits.
- Without a published limit, begin at no more than one request per second per
  host, use bounded concurrency, cache responses, and back off after errors.
- Use conditional requests with `ETag` and `Last-Modified` when the source
  supports them.
- Stop repeated requests when content has not changed.
- Never use residential proxies, deceptive headers, or distributed requests to
  defeat source controls.

## Source register

No adapter enters production without a `Source` and `SourcePolicy` record that
states:

- Owner and canonical URL.
- Whether it is primary, licensed reporting, public reporting, or discovery
  only.
- Access method and endpoint.
- Terms, license, robots, and rate-limit references.
- Permitted collection and publication uses.
- Required attribution.
- Raw-content retention period.
- Collection schedule and concurrency limit.
- Editorial warnings and verification requirements.
- Date and person responsible for the policy decision.

Policy changes create a new version. They do not overwrite the historical
policy applied to an earlier collection.

## Collection record

Every request used by the newsroom records:

- Source and policy version.
- Requested and final URL.
- Request time and completion time.
- HTTP status and response content type.
- Collector identity and adapter version.
- `ETag`, `Last-Modified`, and relevant rate-limit headers.
- Payload hash and byte count.
- Retrieval error, if any.

Redirect chains and failures remain inspectable. Secrets, session cookies, and
authorization headers must never enter logs or stored request metadata.

## Storage and retention

- Store the minimum raw material needed to verify extraction and source-text
  similarity.
- Keep large payloads outside normal database rows and address them by hash.
- Apply the source policy's retention period automatically.
- Preserve claim text, evidence excerpts, hashes, citations, and collection
  metadata needed for published-story audit after a raw payload expires.
- Never commit collected publisher content to Git or distribute it with the
  AGPL repository.
- Primary public records may have longer retention when their terms and public
  status permit it.

## Reporting use

Collection does not make a source claim true. Claims must retain attribution,
time, evidence, and review status. A source may be appropriate for event
discovery but not sufficient evidence for publication.

The story writer receives approved claims and evidence references, not a source
article as a narrative template. Published prose is compared with collected
source text before release. Exclusive reporting is credited and linked rather
than presented as independently confirmed fact.

## Corrections and removal

If a source corrects, retracts, or materially changes a document, the collector
creates a new immutable snapshot and alerts the newsroom. It does not replace
the earlier snapshot. Published claims affected by the change enter the
correction workflow.

A legal or source-owner request is recorded and reviewed. Material is not
quietly removed from audit history, but access to retained raw content may be
restricted while the request is evaluated.

## Initial source

The first adapter uses the Federal Register's public JSON API. It is a primary
government source with structured metadata, stable document identifiers, high
volume, links to official documents, and no need to imitate a browser or parse
a publisher's page.

FederalRegister.gov states that its displayed XML renditions are informational
and that the linked GovInfo PDF is the official electronic edition. The adapter
must preserve that distinction and retain the official PDF URL when supplied.
