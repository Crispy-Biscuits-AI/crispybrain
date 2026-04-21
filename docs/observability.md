# CrispyBrain Observability Model

## Purpose

`v0.5` adds a repo-native observability contract to the current workflow exports without pretending there is a centralized log platform.

The truth source is now:

- structured workflow responses
- `trace` objects appended at boundary stages
- metadata written into existing tables where the workflows already persist state
- offline validation output from `scripts/test-crispybrain-v0_5.sh`

## Trace Contract

Relevant workflows now emit a `trace` object with these fields where practical:

- `run_id`
- `correlation_id`
- `workflow_name`
- `project_slug`
- `source_type`
- `filename`
- `filepath`
- `stage`
- `status`
- `error_code`
- `error_message`
- `timestamp`
- `stage_history`
- `grounding_status`
- `weak_grounding`
- `answer_mode`
- `usage_available`
- `usage_reason`
- `input_tokens`
- `output_tokens`
- `total_tokens`
- `prompt_eval_count`
- `eval_count`

`stage_history` is append-only within the workflow response payload. It is the main repo-native view of stage transitions.

## Token Usage Observability

The current assistant and demo exports treat token usage as part of the observable response contract, not as an estimate layer.

- successful generation copies provider-reported Ollama counts into top-level `usage` and mirrors those values into `trace.input_tokens`, `trace.output_tokens`, and `trace.total_tokens`
- retrieval-empty and insufficient-answer paths keep `usage.available = false` with `null` token fields and `usage_reason = answer_not_generated`
- the demo wrapper preserves a successful answer path with missing upstream generation counts as `usage.available = false` and `usage_reason = upstream_usage_missing`
- failed generation paths keep the token fields explicit and preserve the failure reason rather than leaving stale counts in place

Token usage reflects real model execution when available. When unavailable, CrispyBrain explicitly reports that state instead of estimating.

## Propagation Rules

Use these rules when reading or extending the workflows:

1. The first workflow entrypoint mints `run_id` when the caller did not provide one.
2. `correlation_id` defaults to `run_id` and is preserved across handoffs.
3. Workflow-to-workflow HTTP calls should pass both `run_id` and `correlation_id`.
4. Each workflow keeps its own `workflow_name` in `trace`, so the response tells you which export produced the payload.
5. `trace.stage_history` is appended only at meaningful boundaries such as validation, embedding readiness, retrieval readiness, duplicate detection, and final response assembly.

For the current repo, `run_id` and `correlation_id` usually match unless an external caller provides a separate correlation key.

## Failure Classification

The hardening pass uses a small classification set:

- `validation`: input was malformed or missing required fields
- `duplicate`: replayed ingest was detected and rejected
- `state_conflict`: a partial ingest was detected and requires operator cleanup
- `transient`: safe retry may succeed, typically local Ollama HTTP failures
- `external`: upstream returned malformed or incomplete data
- `upstream`: a dependent workflow returned a structured failure

`retryable` is emitted alongside these classifications where the workflow can tell the difference honestly.

## Where To Inspect

### HTTP / webhook responses

Most workflows now return enough structured data to answer:

- what ran
- which project was targeted
- which file or request was involved
- where the request stopped
- whether the request succeeded, failed, retried, or was rejected
- whether token usage came from a real generation result or was explicitly unavailable

### Stored assistant turns

`assistant` stores `trace`, `run_id`, and `correlation_id` inside `openbrain_chat_turns.metadata_json`.

That makes session debugging possible from the existing table without adding a new logging service.

### Stored ingest metadata

`ingest` now writes `run_id`, `correlation_id`, `workflow_name`, `source_type`, `filepath`, `project_slug`, and `content_hash` into `memories.metadata_json`.

That is what powers duplicate/replay detection in the workflow itself.

## Helpful Commands

Summarize a saved workflow payload:

```bash
node scripts/summarize-crispybrain-run.js /path/to/run.json
```

Or from stdin:

```bash
cat /path/to/run.json | node scripts/summarize-crispybrain-run.js
```

Run the offline repo-grounded checks:

```bash
./scripts/test-crispybrain-v0_5.sh
```

Validate the current token contract:

```bash
node scripts/test-crispybrain-token-contract.js
./scripts/test-crispybrain-v0_9_9_tokens.sh
```

## What This Does Not Claim

`v0.5` does not add:

- centralized log shipping
- a new execution event table
- automatic cleanup for partial ingests
- full runtime observability for every legacy/manual workflow variant

Those are intentionally deferred until the repo has an agreed storage and operator model for them.
