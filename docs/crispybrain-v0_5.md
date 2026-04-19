# CrispyBrain v0.5

## Goal

`v0.5` is a system-first hardening release.

It is focused on:

- observability
- reliability
- correctness

It is not a flashy feature release. The main target is hidden failure at workflow boundaries.

## What Changed

### Observability

The active CrispyBrain workflow exports now use a shared trace contract.

Primary updates:

- webhook-facing workflows mint or preserve `run_id` and `correlation_id`
- responses include `trace.stage_history` so stage transitions are inspectable
- assistant turn persistence now includes trace metadata
- ingest metadata now includes `run_id`, `correlation_id`, `filepath`, `project_slug`, and `content_hash`
- `scripts/summarize-crispybrain-run.js` gives operators a quick way to inspect saved payloads

### Reliability

The hardening pass reduces hidden failures by making boundary behavior explicit.

Key changes:

- ingest input validation now rejects bad payloads with explicit reasons instead of relying on thrown errors
- ingest performs duplicate and partial-ingest detection against existing `memories.metadata_json`
- safe local Ollama HTTP calls now retry conservatively
- assistant, demo, context, validation, and project-memory endpoints emit structured failures instead of weak generic errors
- search and retrieval boundary validation now rejects malformed project slugs earlier

### Correctness

Boundary validation is now testable from the repo alone.

`scripts/test-crispybrain-v0_5.sh` executes exported code-node logic directly from the checked-in workflow JSON and covers:

- valid ingest path
- invalid ingest path
- edge chunking path
- duplicate and partial replay detection
- observability propagation for assistant responses
- retrieval boundary validation for search-by-embedding

## Workflow Coverage

This pass hardens the checked-in exports that matter most to the current CrispyBrain slice:

- `assistant`
- `crispybrain-demo`
- `crispybrain-build-context`
- `ingest`
- `auto-ingest-watch`
- `search-by-embedding`
- `validation-and-errors`
- `project-memory`
- `answer-from-memory`
- `build-context`

Legacy/manual workflow variants remain in the repo, but `v0.5` prioritizes the active boundary workflows rather than rewriting every historical artifact.

## Testing

Run the offline checks:

```bash
./scripts/test-crispybrain-v0_5.sh
```

What the script validates:

- structured trace presence
- explicit reject-with-reason behavior
- duplicate/replay detection
- retry configuration on safe external calls
- existence of the v0.5 operator docs

## Inspecting Results

If you have a saved workflow response:

```bash
node scripts/summarize-crispybrain-run.js /path/to/run.json
```

Or:

```bash
cat /path/to/run.json | node scripts/summarize-crispybrain-run.js
```

The summary output is meant to answer:

- what workflow produced the payload
- which run and correlation ids were used
- what stage the workflow reached
- whether the request succeeded, failed, or was rejected
- which file or project was involved

## Version-Sensitive Notes

This release was hardened against the repo constraints provided for:

- `n8n 2.16.1`
- `Docker Desktop macOS 4.69.0`
- `Ollama 0.18.0`
- `Postgres 16.13` with `pgvector`
- `ARM64 / aarch64`

The workflow changes deliberately stay additive and avoid speculative infrastructure.

## Intentionally Not Implemented Yet

`v0.5` does not add:

- centralized log aggregation
- schema changes for a dedicated run-events table
- automated repair for partial ingests
- a broader architecture rewrite
- new user-facing product features

That work can come later, but the repo now has a real and testable hardening baseline.
