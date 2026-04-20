# Trust Output

## v0.9.2 answer modes

Assistant and demo responses now include `answer_mode`:

- `direct`: strong support was available, so the answer can be returned normally
- `conflict`: retrieved notes disagree, so the assistant reports the disagreement instead of synthesizing a guess
- `insufficient`: support was missing or too weak, so the assistant falls back to the existing insufficient-memory response

## Response fields

`v0.9.2` keeps the `v0.9` output shape and the `v0.9.1` refinements without removing the existing `sources`, `trust`, `grounding`, or `retrieval` blocks:

- `retrieved_candidates`: the ranked candidate set kept visible for inspection
- `selected_sources`: the sources actually carried into the answer decision
- `answer_mode`
- `conflict_flag`
- `conflict_details`
- `conflict_severity`
- `claim_support_counts`
- `most_supported_claim`
- `most_recent_claim`
- `entity_focus`
- `filtered_candidate_count`

`sources` remains present for UI compatibility and continues to represent the visible sources for the answer.

## Conflict behavior

When `answer_mode = conflict`:

- `conflict_flag` is `true`
- `conflict_severity` is either `strong_conflict` or `possible_conflict`
- `conflict_details` lists the conflicting topic/relation plus the competing values, support counts, optional newest timestamps, and source titles
- `claim_support_counts` summarizes how many visible supporting sources back each competing value
- `most_supported_claim` appears only when one claim has the highest support count
- `most_recent_claim` appears only when timestamps exist and one claim is clearly newest
- the assistant answer is constructed from those competing claims directly, now with support counts and non-authoritative hints
- the assistant does not choose a winner

This keeps disagreement explicit instead of hiding it behind a synthesized answer.

## Conflict severity

`v0.9.2` keeps the `v0.9.1` severity layer:

- `strong_conflict`: the same entity/property has clearly different asserted values
- `possible_conflict`: the disagreement is real but more overlapping or ambiguous

If there is no conflict, `conflict_flag` stays `false` and `conflict_severity` is `null`.

## Conflict usefulness hints

The new hint fields are intentionally non-authoritative:

- `claim_support_counts`: visible support counts per competing claim value
- `most_supported_claim`: a hint that one value has more visible support than the others
- `most_recent_claim`: a hint that one value is newer than the others when source timestamps exist

These fields are for operator inspection only.
They do not change `answer_mode`, and they do not let the assistant collapse a conflict into a single answer.

If support is tied, `most_supported_claim` is omitted.
If timestamps are missing or tied, `most_recent_claim` is omitted.

## Entity focus and filtered candidates

When the query exposes a reliable subject, the assistant can now return:

- `entity_focus`: a small object with the inferred `entity`, `property`, and `terms`
- `filtered_candidate_count`: how many raw candidates were trimmed back out before the final visible candidate list

These help explain why:

- a subject-specific factual query now prefers clearly on-topic notes
- generic runtime/build-context notes may disappear from `retrieved_candidates`
- conflict output can stay easier to inspect without losing the true competing sources

## Weak evidence behavior

When a note is retrieved but the support remains weak, the assistant still routes the answer to `answer_mode = insufficient`.

That means the response preserves the existing fallback message:

`I do not have enough stored memory to answer that yet.`

The retrieval is still inspectable through:

- `retrieved_candidates`
- `grounding`
- `trust`

So operators can see that something partial was found without the assistant overstating confidence.
