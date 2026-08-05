# Newsroom Data Model

The News stores the reporting process as a chain of inspectable records. A
published story must be traceable from edition prose back to claims, evidence,
source snapshots, and the source policy in force when each snapshot was
collected.

## Source collection

- `Source` identifies an owner and source family.
- `SourcePolicy` is a versioned decision about access, retention, attribution,
  and permitted use. An approved policy cannot be edited.
- `CollectionRun` records one adapter execution and its outcome.
- `SourceDocument` is the stable identity of a document at a source.
- `DocumentSnapshot` is an append-only observation of that document under a
  specific policy and collection run.

## Reporting

- `EventCluster` groups source documents concerning the same real-world event.
- `Claim` stores one independently reviewable assertion and its state:
  confirmed, attributed, disputed, or unknown.
- `EvidenceItem` connects a claim to an exact snapshot excerpt and records
  whether the evidence supports, contradicts, or contextualizes the claim.
- `Story` is the stable identity of a piece of reporting.
- `StoryVersion` is one version of its prose and generation metadata.
- `StoryClaim` declares exactly which claims a story version uses and how it
  uses them.

## Publication

- `Edition` identifies a dated Top Ten, Complete, or Weekend publication and
  its target reading time.
- `EditionItem` orders approved story versions in the edition.
- `Artifact` records the web, RSS, email, PDF, or EPUB result generated from an
  edition.
- `Delivery` records an attempted publication or delivery without storing a
  plain recipient address in the audit field.
- `Correction` links superseded and corrected story versions to the affected
  edition.

## Accountability

- `EditorialDecision` records a human or autonomous policy decision about any
  newsroom record.
- `AuditEvent` is append-only and supports a hash chain through
  `previous_hash` and `event_hash`.

## Invariants

1. A collector cannot run without an approved source policy.
2. Approved policies and document snapshots are not overwritten.
3. Collection retries use external identifiers and hashes to avoid duplicates.
4. Claims retain their event, status, attribution, and evidence.
5. Story versions declare the claims they use.
6. Editions contain specific story versions, not mutable stories.
7. All format artifacts belong to one edition version.
8. Corrections create new story and edition history rather than erasing the old
   record.
