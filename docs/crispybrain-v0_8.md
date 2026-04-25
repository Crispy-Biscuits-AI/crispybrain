# CrispyBrain v0.8

Status: historical release note. The current docs version is `v1.0.0-14-g59bd5dc`.

`v0.8` is the trust and evaluation release.

It keeps the existing local demo and workflow shape intact while making retrieval support easier for operators to inspect and easier to validate repeatedly.

## What Changed

### Retrieval evaluation harness

The repo now includes a dedicated operator-facing evaluation pack:

```bash
./scripts/test-crispybrain-v0_8.sh
```

The harness:

- imports the checked-in `assistant`, `crispybrain-demo`, and `ingest` workflows
- activates the webhook workflows before evaluation
- seeds a small runtime note pack under `seed-data/runtime`
- runs exactly 8 evaluation cases
- prints terminal-readable pass/fail output with compact diagnostics for each case

The 8 cases cover:

- semantic match
- exact phrase match
- ambiguity / weak query
- no-strong-match query
- near-neighbor / distractor query
- multi-memory style query
- grounding visibility check
- regression-style query

Each case reports:

- case id
- query
- intent/type
- expected behavior
- pass/fail
- compact diagnostic output

### Grounding and evidence visibility

The checked-in `assistant` workflow now returns a top-level `grounding` block alongside the existing retrieval and trust metadata.

The current grounded fields are limited to observable workflow data and include:

- `status`
- `note`
- `reasons`
- `ranking_mode`
- `weak_grounding`
- `evidence_strength`
- `overall_trust_band`
- `primary_memory_ids`
- `primary_chunk_indexes`
- `similarity_threshold`
- `strongest_similarity`
- `reviewed_source_count`
- `supporting_source_count`

The source list is also clearer about evidence already present in the system, including fields such as:

- `id`
- `memory_id`
- `source_label`
- `filename`
- `filepath`
- `chunk_index`
- `total_chunks`
- `review_status`
- `trust_band`
- `similarity`

The local fallback demo page in `docs/crispybrain-v0.4-chat.html` now renders:

- the grounding note
- visible evidence cards
- source trust and review metadata
- chunk and similarity details when returned by the workflow

### Weak-grounding behavior

`v0.8` makes weak support explicit instead of implying confidence.

The current workflow uses simple observable signals only:

- no retrieved memory
- limited supporting sources
- no reviewed sources
- low-trust visible source
- borderline top similarity
- source uncertainty flags already present in the response

The current semantic retrieval floor remains `0.72`.

For weak-grounding purposes, the top semantic match is treated as borderline when its similarity is below `0.77`.

This results in three operator-visible states:

- `grounding.status = grounded`
- `grounding.status = weak`
- `grounding.status = none`

`grounding.status = none` is used when no strong supporting memory was retrieved.

`grounding.status = weak` is used when the answer still has some retrieval support but the current observable signals do not justify a stronger claim.

## How To Run The Evaluation Pack

Run:

```bash
./scripts/test-crispybrain-v0_8.sh
```

Inspect:

- the per-case `result`
- the per-case diagnostic JSON
- `grounding_status`
- `weak_grounding`
- `supporting_source_count`
- `reviewed_source_count`
- `memory_count`
- the top source summary when present

The harness also prints:

- the total case count
- the passed case count
- the failed case count
- a likely failure point
- a smallest next debug step in curl form

## Limitations That Remain

This release does not invent missing evidence fields.

If a desired field is not already available from the current workflow path, it is not surfaced.

That means:

- there is still no fabricated confidence score
- not every answer can claim a strong match
- visible evidence remains limited to the metadata already stored and returned by the current repo-owned workflow path
