# CrispyBrain v0.7

`v0.7` is a stability and observability hardening pass.

`v0.7.1` is a small follow-on patch that resolves the retrieval-policy ambiguity from `v0.7` without widening the repo shape.

It keeps the current retrieval and demo behavior intact while tightening three areas:

- anchor-aware deterministic retrieval ordering inside the checked-in assistant workflow
- script-first memory inspection with exact project, review-status, and time-range filters
- repeated-pass consistency checks in the existing runtime harness

## What Changed

### Anchor-aware deterministic retrieval

The checked-in `assistant` workflow now uses two conservative ranking modes:

- `anchor`: for strong lexical anchors such as exact filename-style probes, quoted titles, or unique title-like anchor tokens
- `semantic`: for the existing broad semantic path when strong anchor evidence is absent

`suppressed` rows remain excluded in both modes.

Anchor mode is designed for note lookup behavior rather than general semantic search.

Inside anchor mode, matching candidates are ordered by:

- strongest title/name anchor evidence first
- then stronger lexical anchor overlap
- then `reviewed` ahead of `unreviewed`
- then `created_at DESC`
- then `id DESC`

Inside semantic mode, the existing project-first path is preserved and made deterministic with:

- project match first when a `project_slug` is provided
- then `reviewed` ahead of `unreviewed`
- then similarity ordering
- then `created_at DESC`
- then `id DESC`

That means recency only decides ties after anchor evidence or similarity have already kept multiple rows eligible.
This patch does not force a global "newest wins" policy.

The workflow also logs:

- inbound query context
- ranking mode (`anchor` or `semantic`)
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

The harness now lives at `scripts/test-crispybrain-v0_7.sh`, with `scripts/test-crispybrain-v0_6.sh` kept as a compatibility wrapper.

It:

- imports and activates the checked-in `workflows/assistant.json` before validation
- reuses the existing cycle count as the consistency pass count
- keeps the safe cap at `12`
- prints the exact pass count
- validates both an exact filename probe and an anchored-but-not-exact lexical query
- normalizes assistant responses for meaningful comparison
- reports drift clearly with hashes and payloads if any pass changes

## Validation Flow

Use:

```bash
./scripts/test-crispybrain-v0_7.sh --cycles 5
```

That run now validates:

- existing ingest and review-state checks
- reviewed-source propagation
- anchor-aware note lookup for strong lexical queries
- deterministic repeated-pass assistant output for both anchor-style and exact filename probes
- inspector support for exact filtered row inspection

## Known Limitation

This release hardens deterministic retrieval and the inspectable output surface inside the repo-controlled path.

It does not claim to redesign the answer model itself beyond the current checked-in workflow behavior.

For broad semantic questions without strong lexical anchors, similarity still governs the main retrieval path and recency only applies as a deterministic fallback after higher-priority ranking signals.
