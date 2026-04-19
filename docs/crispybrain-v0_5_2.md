# CrispyBrain v0.5.2

## Goal

`v0.5.2` is an operator-visibility pass on top of the already verified `v0.5` and `v0.5.1` hardening work.

It adds:

- a script-based Memory Inspection Tool for the live `memories` table
- a configurable repeated-cycle harness so operators can test whether more cycles reveal instability or mostly reconfirm existing behavior

## Memory Inspection Tool

Run the tool with Node:

```bash
node scripts/inspect-crispybrain-memory.js --mode summary
node scripts/inspect-crispybrain-memory.js --mode suspect --limit 10
node scripts/inspect-crispybrain-memory.js --mode clean --json
node scripts/inspect-crispybrain-memory.js --mode export-suspect --out seed-data/suspect-memories.json
```

Supported modes:

- `summary`: total rows, suspect rows, clean rows, suspect IDs, reason counts, and per-project counts
- `suspect`: list rows that fail the current suspect-row rule
- `clean`: list rows that pass the current suspect-row rule
- `export-suspect`: export the current suspect rows as JSON to stdout or a file

Each listed row includes, where available:

- `id`
- `project_slug`
- `title`
- `filename`
- `filepath`
- `content_preview`
- `reason_flagged`
- `content_length`
- `created_at`
- `run_id`
- `correlation_id`

## Suspect-Row Rule

The inspection tool intentionally reuses the same narrow rule already enforced in assistant retrieval.

A row is classified as suspect when its trimmed `content` fails one or more of these checks:

- length under `20`
- contains the Unicode replacement character `�`
- contains fewer than `12` ASCII letters
- contains fewer than `70%` safe plain-text characters under the current repo rule

This is an inspection and retrieval-time classification rule only.

`v0.5.2` does not add destructive cleanup or delete behavior.

## Expanded Cycle Harness

Run:

```bash
./scripts/test-crispybrain-v0_5_1_cycles.sh
./scripts/test-crispybrain-v0_5_1_cycles.sh --cycles 6
```

Cycle count is bounded to a safe range of `3..12`.

Default cycle count: `6`

Each cycle checks:

- invalid ingest rejection
- valid ingest success
- duplicate/replay rejection
- assistant retrieval for the ingested token
- trace propagation
- suspect-row exclusion from returned sources

The script also compares memory summaries before and after the run to answer a bounded repeatability question:

- did more cycles add only the expected clean rows
- or did later cycles start to produce failures, new suspect rows, or materially worse latency

## How To Interpret “More Cycles”

More cycles are useful when they reveal one of these signals:

- failures appear only after repeated runs
- suspect row count increases unexpectedly
- assistant sources begin leaking suspect rows
- later-cycle latency becomes materially worse than earlier cycles

If those signals do not appear, a larger run mostly reconfirms stability rather than uncovering new behavior.

## Upstream Boundary

The known `dbTime.getTime is not a function` issue remains treated as upstream/external to CrispyBrain in this pass.

Unless a repo-owned trigger is proven with runtime evidence, `v0.5.2` does not attempt speculative local fixes for that n8n issue.
