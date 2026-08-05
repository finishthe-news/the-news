# The News

The News is a finite, evidence-first daily publication at `finishthe.news`.
Its promise is "Finish the news." The canonical product and editorial mission
is [docs/LAUNCH_MISSION.md](docs/LAUNCH_MISSION.md). Read it before making
product, editorial, ingestion, generation, delivery, or interface decisions.

## Start every task

1. Run `hostname && pwd` and confirm this checkout is
   `/home/ritz/projects/the-news` on Ritz.
2. Read this file and `docs/LAUNCH_MISSION.md` completely.
3. Check `git status --short --branch` before changing files.
4. Read the manifest, lockfile, tests, and nearby code before choosing tools or
   commands.
5. State material assumptions and define how the requested result will be
   verified.

This is one AGPL Rails repository. The accepted application architecture is
recorded in
[docs/architecture/0001-rails-sqlite-monolith.md](docs/architecture/0001-rails-sqlite-monolith.md).
Do not split the application into additional repositories or services without
an approved architecture decision. Payment, email, and LLM providers remain
undecided and must not become structural dependencies without approval.

## Fixed product decisions

- The free weekday product is **The Top Ten**, with ten stories and
  approximately 10 to 15 minutes of reading.
- The paid weekday product is **The Complete Edition**, with approximately 45
  minutes of reading.
- The paid **Weekend Edition** is published Friday evening and contains
  approximately two hours of magazine-style reading.
- Launch pricing is $10 per month or $100 per year, preceded by a 14-day trial
  of the complete product.
- Every edition supports web, RSS, email, printable PDF, and EPUB.
- All formats render from one approved edition record. Format renderers must
  not independently rewrite reporting.
- The website has no ads, no infinite scroll, and no engagement content after
  the finish line.
- The public finish message is exactly:

  > **You've finished today's news.**<br>
  > The next edition arrives tomorrow.

- The AGPL engine defaults to autonomous operation.
- The official hosted publication requires human approval at launch through an
  installable editorial PWA.
- The initial stack is Rails 8.1, Hotwire, SQLite, Solid Queue, and Kamal.
- The canonical checkout and Docker build run on Ritz. Web and worker
  containers run on Hetzner.

Do not reduce the launch to a web-only or email-only demonstration. The launch
standard in the mission document is the required product boundary unless Robert
explicitly changes it.

## Editorial requirements

Daily reporting uses the inverted pyramid. Every story must establish:

1. What happened.
2. What is confirmed.
3. Who says what.
4. Why it matters.
5. What remains uncertain.
6. Evidence and sources.

Spin is prohibited. Analysis and opinion must be labeled. Allegations stay
attributed. Corrections are visible and versioned. Never silently replace
published text.

Weekend reporting may use magazine-style narrative structures, but it remains
evidence-backed. Do not use "editorial" as a synonym for magazine-style when it
could be mistaken for institutional opinion.

## Copyright and source boundary

Never implement a "rewrite this article" path.

The writing stage receives verified atomic claims, evidence references,
required attribution, approved quotations, and context. It must not receive a
publisher's article as a narrative template. Compare final prose against all
collected source text before publication.

- Prefer primary sources.
- Credit and link original reporting.
- Clearly attribute exclusive reporting that cannot be independently
  confirmed.
- Do not launder an exclusive report through sites repeating it.
- Respect access controls, licenses, source terms, and retention rules.
- Keep raw publisher articles and copyrighted test fixtures out of Git.
- Use synthetic fixtures or material that is clearly licensed for tests.
- Do not treat claim extraction, blind drafting, fair use, or geographic
  blocking as an automatic legal safe harbor.
- Do not redistribute collected source material with the AGPL software.

Any new source adapter must declare its access method, permissions or terms,
retention policy, and allowed uses before it can enter the production source
register.

## Architecture invariants

Preserve this boundary unless a reviewed design explicitly replaces it:

```text
sources
  -> event clusters
  -> atomic claims and evidence
  -> contradiction and uncertainty review
  -> editorial selection
  -> original story draft
  -> factual, attribution, and similarity checks
  -> required human approval
  -> canonical edition
  -> web, RSS, email, PDF, and EPUB
```

- Store provenance at claim level.
- Distinguish confirmed, attributed, disputed, and unknown claims in data, not
  only in prose.
- Preserve immutable publication and audit history.
- Corrections must identify every affected story, edition, and output.
- Publication must fail closed when required evidence, approval, or rendering
  is missing.
- Autonomous and human-reviewed operation share the same pipeline. Human review
  is a publication policy, not a separate implementation.
- Never let delivery formats drift into separate editorial versions.

## Editorial PWA

The editor must be able to review clusters, inspect claims beside evidence,
resolve warnings, edit or regenerate selected passages, approve stories,
assemble the edition, publish all formats, and issue corrections.

The desk must surface single-source claims, contradictions, stale evidence,
close language matches, missing attribution, and high-risk subjects. Strong
authentication and an append-only audit trail are required. Publishing requires
a live connection.

## Suggested repository structure

Use this as an organizational starting point. Do not create empty architecture
or abstractions merely to match the tree.

```text
.
├── AGENTS.md
├── README.md
├── docs/
│   ├── LAUNCH_MISSION.md
│   ├── architecture/
│   ├── editorial/
│   ├── product/
│   └── operations/
├── apps/
│   ├── web/
│   └── editorial/
├── services/
│   ├── ingestion/
│   ├── newsroom/
│   └── delivery/
├── packages/
│   ├── schemas/
│   ├── editorial-rules/
│   └── renderers/
├── tests/
├── config/
└── .kamal/
```

The final structure should follow the chosen stack and the simplest design
that preserves the required boundaries.

## Working rules

- Make the smallest complete change that satisfies the request.
- Do not add speculative features or providers.
- Match the established style once the codebase exists.
- Keep unrelated changes and runtime data intact.
- Add a failing test before fixing a defect when practical.
- Test invalid and disputed editorial states, not only the successful path.
- Use `uv` for Python projects. Do not use `pip`, Poetry, Conda, or a manually
  managed virtual environment.
- For JavaScript or TypeScript, follow the committed lockfile and required Node
  version.
- Never read, print, or commit plaintext secrets.
- Do not commit, push, deploy, publish an edition, send email, charge a payment
  method, or alter production data unless Robert asks.

## Verification

Verification must match the risk of the change. Relevant checks can include:

- Unit and integration tests.
- Schema validation.
- Claim-to-evidence completeness.
- Attribution and quotation fidelity.
- Source-text similarity checks.
- Reading-time budgets.
- Cross-format content equality.
- Accessibility and responsive reading tests.
- Light and dark system-color behavior.
- PWA installability and authentication.
- Failure behavior for missing evidence, missing approval, and partial delivery.
- Correction propagation and audit history.

Report the exact checks run and their results. A successful generation call,
build, deploy command, or HTTP response does not by itself prove editorial or
delivery correctness.
