# CrispyBrain v0.5.1

Status: historical release note. The current docs version is `v1.0.0-14-g59bd5dc`.

## Goal

`v0.5.1` is a narrow stability pass on top of the already verified `v0.5` hardening work.

It focuses on:

- keeping obviously corrupted memory rows out of assistant retrieval/context output
- proving repeated ingest → assistant cycles remain stable
- leaving the known `dbTime.getTime is not a function` issue in the upstream bucket unless repo evidence says otherwise

## Suspect Row Rule

The assistant retrieval path now reuses the same deterministic content sanity rule that already existed in `crispybrain-build-context`.

A memory row is treated as suspect for retrieval/context assembly when its `content` fails one of these checks:

- content length under `20`
- contains the Unicode replacement character `�`
- contains fewer than `12` ASCII letters
- has less than `70%` safe plain-text characters under the current repo rule

This is a retrieval-time skip, not a destructive delete.

The intent is to narrowly exclude obviously garbled rows such as short binary-looking fragments while keeping valid text rows searchable.

## Repeatability Check

Run:

```bash
./scripts/test-crispybrain-v0_5_1_cycles.sh
```

The script verifies:

- invalid ingest still rejects with structured trace output
- valid ingest succeeds repeatedly
- immediate replay still rejects as `DUPLICATE_INGEST`
- assistant responses preserve `correlation_id` and include `run_id`
- assistant retrieval sources do not include rows flagged by the v0.5.1 suspect-row rule

## Live Runtime Notes

`v0.5.1` is intentionally additive:

- no schema redesign
- no casual data deletion
- no workflow renames

The repo remains the source of truth; workflow updates should still be applied through exported JSON plus n8n CLI import.

## Upstream Boundary

The known `dbTime.getTime is not a function` issue remains treated as an upstream/external n8n item for this pass.

Unless a repo-owned trigger is proven with runtime evidence, `v0.5.1` does not attempt speculative n8n internals patches or local workarounds for it.
