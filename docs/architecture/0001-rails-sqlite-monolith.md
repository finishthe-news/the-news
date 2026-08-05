# ADR 0001: Rails monolith with SQLite

**Status:** Accepted<br>
**Date:** 2026-08-04

## Context

The News will launch as one application on one Hetzner server. It needs a fast
public reading site, an installable editorial desk, scheduled collection and
generation work, subscriptions, email, and five render formats. The software
must also be practical for one person to self-host.

The expected workload has many reads and scheduled bursts of writes. It does
not initially require multiple application servers or concurrent database
writers spread across hosts.

## Decision

Build one Rails 8.1 application with Hotwire, Active Record, and SQLite. Use
Rails' separate SQLite databases for application data, jobs, cache, and cable.
Use Solid Queue for recurring and background work.

Deploy one application image with separate Kamal roles:

- `web` serves the public publication and editorial PWA.
- `worker` runs collection, newsroom, rendering, and delivery jobs.

Ritz holds the canonical checkout and builds the image. Hetzner runs the web
and worker containers and stores persistent SQLite files and generated
artifacts on a mounted data directory.

This is a modular monolith. Ingestion, newsroom, editorial, rendering, billing,
and delivery code have clear module boundaries, but they share one repository,
application, and data model.

## Why SQLite

- It removes a database server, credentials, network connection, and service
  from the initial operating system.
- It matches a single-host publication with modest interactive write traffic.
- It makes the AGPL application easier to run locally and self-host.
- Rails 8.1 supports production SQLite and separates queue, cache, and cable
  traffic from the primary application database.
- Active Record migrations preserve a practical path to PostgreSQL later.

SQLite allows only one writer to a database at a time. We accept that limit and
will keep write transactions short, make jobs idempotent, control worker
concurrency, and avoid long database work inside model callbacks.

## Operating rules

- Never put a live SQLite database on a network filesystem.
- Persist every production database under the dedicated Hetzner data mount.
- Back up databases with a SQLite-aware process. Do not assume that copying a
  live database file alone captures a consistent write-ahead log state.
- Keep source payloads and generated artifacts outside database rows when they
  are large. Store their hashes and locations in the database.
- Give collection jobs explicit concurrency limits per source and keep their
  database writes small.
- Use unique constraints and content hashes so retries do not duplicate source
  documents, snapshots, claims, artifacts, or deliveries.
- Treat `SQLite3::BusyException` and lock-wait measurements as operational
  signals, not errors to hide with unlimited retries.

## PostgreSQL migration triggers

Move the primary application database to PostgreSQL when one or more of these
conditions becomes true:

1. The publication needs more than one web or worker host writing to the same
   application database.
2. Normal job concurrency causes repeated database lock timeouts after queries
   and transactions have been corrected.
3. Required collection or publication throughput cannot meet the edition
   deadline with controlled write concurrency.
4. Backup, restore, reporting, or replication requirements exceed a
   single-host SQLite design.
5. A required feature depends on PostgreSQL behavior that cannot be provided
   cleanly in SQLite.

The queue, cache, and cable databases may remain SQLite even if the primary
application database moves, unless their own operating evidence calls for a
change.

## Consequences

The first deployment has fewer moving parts and is easier to self-host. The
application must measure lock failures, queue latency, edition completion time,
database size, and backup duration from the beginning. A later PostgreSQL
migration is acceptable; operating both databases without evidence that we
need both is not.
