# ADR 0003: Provisional editorial scoring model

**Status:** Accepted for development<br>
**Date:** 2026-08-11

## Decision

Use the exact dated model `deepseek/deepseek-v4-flash-0731` for editorial
cluster scoring during development.

The current reviewed request configuration is:

- Fireworks provider route, with no unreviewed provider fallback.
- Per-request zero data retention required.
- Provider data collection denied.
- Reasoning explicitly disabled.
- Strict JSON Schema response required and locally validated.

Do not use the mutable `latest` model alias. Model, provider, reasoning, prompt,
schema, and rubric changes require a new comparison run.

## Evidence and limitations

On the six-source Nizhnekamsk dossier, the model returned schema-valid output
for $0.000896, compared with $0.00516675 for `openai/gpt-5.4-mini`. It agreed on
section and three of five scores, but scored geographic reach and novelty one
point higher. This is sufficient to make it the provisional development model,
not evidence of autonomous editorial accuracy.

The Fireworks route succeeded after reasoning was disabled. A Wafer route with
strong catalog uptime returned HTTP 429, demonstrating that catalog health does
not guarantee serving capacity. A reviewed ZDR provider allowlist may replace
the single route after availability behavior is tested without changing the
model decision.
