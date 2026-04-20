# Trust Output

## v0.9 answer modes

Assistant and demo responses now include `answer_mode`:

- `direct`: strong support was available, so the answer can be returned normally
- `conflict`: retrieved notes disagree, so the assistant reports the disagreement instead of synthesizing a guess
- `insufficient`: support was missing or too weak, so the assistant falls back to the existing insufficient-memory response

## New response fields

`v0.9` adds these top-level fields without removing the existing `sources`, `trust`, `grounding`, or `retrieval` blocks:

- `retrieved_candidates`: the ranked candidate set kept visible for inspection
- `selected_sources`: the sources actually carried into the answer decision
- `answer_mode`
- `conflict_flag`
- `conflict_details`

`sources` remains present for UI compatibility and continues to represent the visible sources for the answer.

## Conflict behavior

When `answer_mode = conflict`:

- `conflict_flag` is `true`
- `conflict_details` lists the conflicting topic/relation plus the competing values and source titles
- the assistant answer is constructed from those competing claims directly
- the assistant does not choose a winner

This keeps disagreement explicit instead of hiding it behind a synthesized answer.

## Weak evidence behavior

When a note is retrieved but the support remains weak, `v0.9` now routes the answer to `answer_mode = insufficient`.

That means the response preserves the existing fallback message:

`I do not have enough stored memory to answer that yet.`

The retrieval is still inspectable through:

- `retrieved_candidates`
- `grounding`
- `trust`

So operators can see that something partial was found without the assistant overstating confidence.
