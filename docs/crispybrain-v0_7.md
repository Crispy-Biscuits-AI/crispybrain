# CrispyBrain v0.7

`v0.7` is a stability and observability hardening pass.

It keeps the current retrieval and demo behavior intact while tightening three areas:

- deterministic reviewed-first retrieval ordering inside the checked-in assistant workflow
- script-first memory inspection with exact project, review-status, and time-range filters
- repeated-pass consistency checks in the existing runtime harness

## What Changed

### Deterministic retrieval hardening

The checked-in `assistant` workflow now makes candidate retrieval deterministic with explicit ordering:

- `reviewed` rows ahead of `unreviewed`
- then existing similarity ordering
- then `created_at DESC`
- then `id DESC`

`suppressed` rows remain excluded.

The workflow also logs:

- inbound query context
- retrieval candidate summaries
- selected context/source summaries
- final response summaries

The logs are surgical and avoid changing the main response shape.

### Memory inspection tool

The existing inspector remains the source of truth and now supports an exact row-inspection mode:

```bash
node scripts/inspect-crispybrain-memory.js --mode inspect --project-slug alpha --review-status reviewed --since 2026-01-01T00:00:00Z --limit 5 --json
```

The `inspect` mode returns real stored fields only:

- `id`
- `title`
- `content`
- `review_status`
- `project_slug`
- `created_at`
- `metadata_json`

Filters:

- `--project-slug`
- `--review-status`
- `--since`
- `--until`
- `--limit`

The underlying query is an exact Postgres query against `memories`, ordered by `created_at DESC, id DESC`.

### Harness consistency passes

The existing `scripts/test-crispybrain-v0_6.sh` harness now performs repeated assistant passes after the ingest/review cycle checks.

It:

- reuses the existing cycle count as the consistency pass count
- keeps the safe cap at `12`
- prints the exact pass count
- normalizes assistant responses for meaningful comparison
- reports drift clearly with hashes and payloads if any pass changes

## Validation Flow

Use:

```bash
./scripts/test-crispybrain-v0_6.sh --cycles 4
```

That run now validates:

- existing ingest and review-state checks
- reviewed-source propagation
- deterministic repeated-pass assistant output for the normalized response payload
- inspector support for exact filtered row inspection

## Known Limitation

This release hardens deterministic retrieval and the inspectable output surface inside the repo-controlled path.

It does not claim to redesign the answer model itself beyond the current checked-in workflow behavior.
