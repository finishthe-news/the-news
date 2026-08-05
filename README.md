# The News

The News is a finite, evidence-first daily publication. Its promise is simple:
finish the news.

The product and editorial commitments are recorded in
[docs/LAUNCH_MISSION.md](docs/LAUNCH_MISSION.md). Contributor and agent rules
are in [AGENTS.md](AGENTS.md).

## Current foundation

- Ruby on Rails 8.1.
- Hotwire public site and editorial PWA.
- SQLite application, queue, cache, and cable databases.
- Solid Queue scheduled and background work.
- One repository and one application image.
- Kamal web and worker roles on Hetzner.
- AGPL-3.0 license.

The accepted architecture decision is
[docs/architecture/0001-rails-sqlite-monolith.md](docs/architecture/0001-rails-sqlite-monolith.md).
The collection rules are in
[docs/editorial/SOURCE_COLLECTION_POLICY.md](docs/editorial/SOURCE_COLLECTION_POLICY.md).

## Development

The application is intended to run in its pinned Docker environment. Prepare
the databases and run the test suite with the repository image once it has
been built:

```bash
bin/rails db:prepare
bin/rails test
```

Do not enable a source collector until its source and approved policy are in
the source register.
