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

## Local CI

GitHub Actions is not used. Run the complete CI gate locally in the pinned
Docker environment:

```bash
docker build --target ci -t the-news:ci .
docker run --rm --user "$(id -u):$(id -g)" --env HOME=/tmp --volume "$PWD:/rails" --workdir /rails the-news:ci bin/ci
```

The gate starts from a clean test database, then runs Ruby style checks, gem
and importmap vulnerability audits, Brakeman, Rails tests, seed validation, and
real system tests when `test/system/**/*_test.rb` contains any.

Do not enable a source collector until its source and approved policy are in
the source register.
