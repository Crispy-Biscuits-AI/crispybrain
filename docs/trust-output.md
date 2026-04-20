# Trust Output

## v0.9.4 answer modes

Assistant and demo responses now include `answer_mode`:

- `direct`: strong support was available, so the answer can be returned normally
- `conflict`: retrieved notes disagree, so the assistant reports the disagreement instead of synthesizing a guess
- `insufficient`: support was missing or too weak, so the assistant falls back to the existing insufficient-memory response

## Response fields

`v0.9.4` keeps the `v0.9` output shape and the `v0.9.3` refinements without removing the existing `sources`, `trust`, `grounding`, or `retrieval` blocks:

- `retrieved_candidates`: the ranked candidate set kept visible for inspection
- `selected_sources`: the sources actually carried into the answer decision
- `answer_mode`
- `conflict_flag`
- `conflict_details`
- `conflict_severity`
- `claim_support_counts`
- `claim_support_counts_raw`
- `claim_support_counts_deduped`
- `claim_weighted_support`
- `dominant_claim_status`
- `dominant_claim_basis`
- `claim_confidence`
- `conflict_summary_hint`
- `most_supported_claim`
- `most_recent_claim`
- `source_quality_breakdown`
- `entity_focus`
- `filtered_candidate_count`

`sources` remains present for UI compatibility and continues to represent the visible sources for the answer.

## Conflict behavior

When `answer_mode = conflict`:

- `conflict_flag` is `true`
- `conflict_severity` is either `strong_conflict` or `possible_conflict`
- `conflict_details` lists the conflicting topic/relation plus the competing values, raw, deduped, and weighted support, optional newest timestamps, and source titles
- `claim_support_counts` continues to expose the support counts used by the assistant, and in `v0.9.4` it matches the deduped view
- `claim_support_counts_raw` shows the visible source count before duplicate suppression
- `claim_support_counts_deduped` shows the duplicate-aware count used for dominant/tie handling
- `claim_weighted_support` shows the summed source-quality weights for each claim after duplicate suppression
- `dominant_claim_status` is `dominant`, `tie`, or `unclear`
- `dominant_claim_basis` is `weighted_support`, `deduped_support`, `tie`, or `unclear`
- `claim_confidence` is a conservative heuristic label, not a probability
- `conflict_summary_hint` gives a deterministic one-line interpretation of the split evidence
- `most_supported_claim` appears only when one claim has the strongest current basis and can now include the basis plus weighted support
- `most_recent_claim` appears only when timestamps exist and one claim is clearly newest
- `sources` and `selected_sources` now expose deterministic `source_quality` and `source_quality_weight` fields
- the assistant answer is constructed from those competing claims directly, now with raw, deduped, and weighted support plus non-authoritative hints
- the assistant does not choose a winner

This keeps disagreement explicit instead of hiding it behind a synthesized answer.

## Conflict severity

`v0.9.3` keeps the `v0.9.1` severity layer:

- `strong_conflict`: the same entity/property has clearly different asserted values
- `possible_conflict`: the disagreement is real but more overlapping or ambiguous

If there is no conflict, `conflict_flag` stays `false` and `conflict_severity` is `null`.

## Source quality rubric

`v0.9.4` adds a deterministic `source_quality` label to the visible sources used in conflict evaluation.

Allowed values:

- `high`
- `medium`
- `low`

The current rubric is intentionally simple and inspectable:

- `high`: reviewed, on-scope, and clearly specific to the entity/property or anchor in question
- `medium`: usable but less direct or less specific
- `low`: duplicate-like, generic runtime/build-context, or otherwise noisy enough that the source should carry less weight

This rubric is heuristic only.
It is not a truth score and it does not change `answer_mode`.

## Conflict usefulness hints

The new hint fields are intentionally non-authoritative:

- `claim_support_counts_raw`: visible support counts before duplicate suppression
- `claim_support_counts_deduped`: duplicate-aware support counts used for tie handling and confidence
- `claim_weighted_support`: quality-weighted support totals derived from visible sources
- `dominant_claim_status`: whether one claim is dominant, tied, or still unclear
- `dominant_claim_basis`: whether the dominant hint came from `weighted_support`, `deduped_support`, `tie`, or `unclear`
- `claim_confidence`: a conservative heuristic summary of how separated the weighted or deduped counts are
- `conflict_summary_hint`: a deterministic plain-language summary of the current split evidence
- `most_supported_claim`: a hint that one value has the strongest current dominance basis
- `most_recent_claim`: a hint that one value is newer than the others when source timestamps exist
- `source_quality_breakdown`: a compact summary of how many visible supporting sources landed in each quality bucket

These fields are for operator inspection only.
They do not change `answer_mode`, and they do not let the assistant collapse a conflict into a single answer.
They are not truth scores and they are not probability estimates.

If support is tied, `most_supported_claim` is omitted.
If timestamps are missing or tied, `most_recent_claim` is omitted.
If stronger weighted support, deduplicated support, and recency point in different directions, `conflict_summary_hint` calls that out explicitly.

## Weighted support

`claim_weighted_support` is built from the visible supporting sources for each claim.

The current fixed weights are:

- `low = 1.0`
- `medium = 1.5`
- `high = 2.0`

Weighted support is computed after duplicate suppression.
That means duplicate-like notes remain visible in raw counts but do not multiply the weighted total unfairly.

The dominance logic is conservative:

1. Compare `claim_weighted_support` first.
2. If one claim is clearly higher, `dominant_claim_status = dominant` and `dominant_claim_basis = weighted_support`.
3. If weighted support ties, fall back to `claim_support_counts_deduped`.
4. If deduped support breaks the tie, `dominant_claim_basis = deduped_support`.
5. If both stay tied, `dominant_claim_status = tie` and `dominant_claim_basis = tie`.
6. If the data is too weak to interpret cleanly, both stay `unclear`.

This is still a heuristic ordering aid for operators.
It is not probabilistic ranking and it is not truth selection.

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
