# CrispyBrain v0.6

Status: historical release note. The current docs version is `v1.0.0-14-g59bd5dc`.

## Goal

`v0.6` is a knowledge-quality and operator-control release.

It focuses on:

- honest visibility into stored memory quality
- explicit operator review state control
- clearer trust indicators on memory-backed answers
- simple trendable health snapshots without inventing new infrastructure

## Release Summary

`v0.6` is the release where CrispyBrain starts exposing memory quality and operator control directly in the checked-in repo surface.

In practical terms, the validated `v0.6` state includes:

- project memory health visibility through the upgraded inspector
- source quality indicators in assistant and demo responses
- operator control over review state without a destructive schema change
- suspect review/export workflows for local inspection
- file-based metrics snapshots over time
- a multi-cycle runtime harness that exercises ingest, duplicate rejection, suppression, review-state updates, and response metadata

## What Changed

### 1. Memory health summary

The memory inspection tool now supports project-aware health summaries with:

- `project_slug`
- total memory rows
- rows by `source_type`
- rows by `review_status`
- suspect row counts
- low-confidence row counts
- duplicate-candidate row counts
- recent ingest activity
- recent review activity when review metadata exists
- a simple verdict band: `healthy`, `warning`, or `needs-review`

### 2. Review state model

`v0.6` introduces a backward-compatible review state model using `memories.metadata_json`:

- `review_status`
- `review_updated_at`
- `review_note`

Supported statuses:

- `unreviewed`
- `reviewed`
- `suspect`
- `suppressed`

The model is additive and does not require a destructive schema change.

Rows are only excluded from assistant retrieval when an operator explicitly marks them `suppressed`.

### 3. Source quality indicators

The assistant response path now includes grounded source trust fields such as:

- `source_type`
- `created_at`
- `review_status`
- `project_match`
- `content_length`
- `chunk_size_band`
- `trust_band`
- `confidence_band`
- `quality_flags`
- `uncertainty_indicator`
- `uncertainty_reasons`

The response also includes a response-level `trust` block so operators can see whether an answer is strongly supported or still uncertain.

### 4. Suspect review/export workflow

The memory inspection tool now supports:

- suspect row listing
- clean row listing
- project filtering
- JSON export
- CSV export
- timestamped export filenames
- explicit review-state updates for selected row IDs

Exports default to repo-local paths under `seed-data/exports/`.

### 5. Metrics over time

Health snapshots are stored as timestamped JSON files under `seed-data/metrics/`.

This is intentionally file-based rather than DB-backed:

- simpler to inspect locally
- no migration risk
- easy to diff or archive

Tradeoff:

- snapshots are operator artifacts, not a queryable metrics table inside Postgres

### 6. Demo output visibility

The `crispybrain-demo` workflow now passes through:

- retrieval summary
- trust summary
- operator capability hints

This makes the visible demo/test output show the v0.6 quality layer without requiring a frontend rewrite.

### 7. Runtime validation and stabilization

The checked-in `v0.6` state was stabilized with the runtime harness hotfix that separated two different concerns:

- retrieval ranking correctness
- metadata correctness for whatever rows were actually retrieved

That distinction matters because a reviewed row can be stored and surfaced correctly without necessarily becoming the top-ranked retrieval result for a broad semantic query.

## Memory Inspection Tool

Run:

```bash
node scripts/inspect-crispybrain-memory.js --mode summary
node scripts/inspect-crispybrain-memory.js --mode project-health --project-slug alpha --json
node scripts/inspect-crispybrain-memory.js --mode suspect --project-slug alpha --limit 10
node scripts/inspect-crispybrain-memory.js --mode export-suspect --project-slug alpha --format csv
node scripts/inspect-crispybrain-memory.js --mode snapshot-health --project-slug alpha
node scripts/inspect-crispybrain-memory.js --mode set-review-status --ids 55 --status reviewed --note "operator review"
```

## Suspect-Row Rule

The suspect-row rule remains intentionally narrow:

- trimmed content length under `20`
- contains the replacement character `�`
- fewer than `12` ASCII letters
- fewer than `70%` safe plain-text characters

`v0.6` extends operator visibility around that rule, but it does not broaden the rule speculatively.

## Key Lesson

The main `v0.6` runtime lesson is that retrieval ranking and metadata correctness are separate concerns.

The harness hotfix kept the ranking check and the review-status propagation check distinct:

- broad anchor-style queries remain useful for checking retrieval quality and source metadata consistency
- deterministic filename-style queries are a better way to prove that a reviewed row is surfaced with the correct `review_status`

This keeps the release honest about what is already true today versus what still belongs in a later ranking pass.

## Operator Page Status

There is not a safe editable operator UI surface inside the allowed paths for this task.

Because of that, `v0.6` ships:

- the backend/data layer
- demo-visible trust fields
- repo-local inspection/export/snapshot tooling

The dedicated operator page is deferred rather than forced into a risky frontend rewrite.

## Known Limitations

Current limitations remain explicit:

- there is no full operator UI yet
- retrieval ranking is not yet quality-aware
- review state mainly affects suppression, not ranking

This means a reviewed memory can still lose to older unreviewed memories on a broad similarity query even when the response metadata is correct.

## Likely v0.7 Direction

The next logical step after `v0.6` is not more metadata alone, but using that metadata more directly in retrieval and operator workflows.

Likely `v0.7` themes:

- quality-aware retrieval ranking
- lightweight operator UI
- automated quality scoring
- feedback loops from review outcomes back into ingestion

## v0.6 Runtime Check

Use:

```bash
./scripts/test-crispybrain-v0_6.sh
./scripts/test-crispybrain-v0_6.sh --cycles 6
```

The harness verifies:

- invalid ingest rejection
- valid ingest success
- duplicate/replay rejection
- explicit review-state updates
- explicit suppression control
- trust indicators in assistant responses
- project health summary generation
- suspect export generation
- metrics snapshot generation
- deterministic reviewed-row propagation checks
