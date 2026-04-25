# Trust Output

Current version: `v1.0.0-14-g59bd5dc`

Status: this document describes the current trust/grounding/trace surface. Version labels such as `v0.9.5` and `v0.9.9` are historical behavior-introduction notes, not the current docs version.

## v0.9.5 answer modes

Assistant and browser responses now include `answer_mode`:

- `direct`: strong support was available, so the answer can be returned normally
- `conflict`: retrieved notes disagree, so the assistant reports the disagreement instead of synthesizing a guess
- `insufficient`: support was missing or too weak, so the assistant falls back to the existing insufficient-memory response

## Response fields

`v0.9.5` keeps the `v0.9` output shape and the `v0.9.4` refinements without removing the existing `sources`, `trust`, `grounding`, or `retrieval` blocks:

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
- `claim_independent_support`
- `claim_independence_adjusted_support`
- `dominant_claim_status`
- `dominant_claim_basis`
- `claim_confidence`
- `conflict_summary_hint`
- `most_supported_claim`
- `most_recent_claim`
- `source_quality_breakdown`
- `source_independence_breakdown`
- `evidence_clusters`
- `entity_focus`
- `filtered_candidate_count`

`sources` remains present for UI compatibility and continues to represent the visible sources for the answer.

## Token and trace visibility

`usage` now travels beside `sources`, `trust`, `grounding`, and `trace` in the current assistant and demo responses.

- generated answers with provider counts return `usage.available = true` and numeric token fields
- those same token counts are mirrored into `trace.input_tokens`, `trace.output_tokens`, and `trace.total_tokens`
- insufficient/no-answer responses keep `answer_mode = insufficient`, `usage.available = false`, and `usage.reason = answer_not_generated`
- the demo wrapper also preserves the explicit `upstream_usage_missing` state when a successful upstream answer omits generation counts

Token usage reflects real model execution when available. When unavailable, CrispyBrain explicitly reports that state instead of estimating.

## v0.9.9 explanation layer

The demo UI now adds a human-readable explanation layer above the existing answer text and keeps the raw trace drawer intact underneath it.

The explanation layer reads directly from existing response fields:

- `grounding.status` drives the visible confidence indicator
- `selected_sources` drives the visible source count and source cards
- `retrieved_candidates` still informs the operator-facing source summary and trace counts
- `grounding.note` is surfaced as the visible uncertainty note in `Why this answer` whenever grounding is weak
- `usage` and `trace.*_tokens` drive the visible token row when generation counts are available

The confidence label is intentionally literal:

- `grounding.status = grounded` renders `High confidence`
- `grounding.status = weak` renders `Limited confidence`
- `grounding.status = none` renders `No evidence`

The UI does not invent a numeric score.
It only translates the existing trust state into faster-to-scan language for a first-time user.
It also does not invent token counts when the backend did not return them.

The sources panel remains inspectable, but the visible source cards are now easier to read:

- filename shown as the card title
- chunk label shown explicitly when available
- preview shortened to a quick readable excerpt
- relevance shown directly from the available retrieval score when present
- existing review, quality, and independence metadata kept visible as badges

## Conflict behavior

When `answer_mode = conflict`:

- `conflict_flag` is `true`
- `conflict_severity` is either `strong_conflict` or `possible_conflict`
- `conflict_details` lists the conflicting topic/relation plus the competing values, raw, deduped, and weighted support, optional newest timestamps, and source titles
- `claim_support_counts` continues to expose the support counts used by the assistant, and in `v0.9.4` it matches the deduped view
- `claim_support_counts_raw` shows the visible source count before duplicate suppression
- `claim_support_counts_deduped` shows the duplicate-aware count used for dominant/tie handling
- `claim_weighted_support` shows the summed source-quality weights for each claim after duplicate suppression
- `claim_independent_support` shows how many evidence clusters support each claim
- `claim_independence_adjusted_support` discounts correlated notes inside the same cluster instead of letting them count like fully independent corroboration
- `dominant_claim_status` is `dominant`, `tie`, or `unclear`
- `dominant_claim_basis` is `independence_adjusted_support`, `weighted_support`, `deduped_support`, `tie`, or `unclear`
- `claim_confidence` is a conservative heuristic label, not a probability
- `conflict_summary_hint` gives a deterministic one-line interpretation of the split evidence
- `most_supported_claim` appears only when one claim has the strongest current basis and can now include the basis plus weighted support
- `most_recent_claim` appears only when timestamps exist and one claim is clearly newest
- `sources` and `selected_sources` now expose deterministic `source_quality` and `source_quality_weight` fields
- `sources` and `selected_sources` now also expose deterministic `source_independence` fields
- `source_independence_breakdown` summarizes how many visible supporting sources are independent, related, duplicate-like, or unclear
- `evidence_clusters` shows the grouped support the assistant used for correlation-aware counting
- the assistant answer is constructed from those competing claims directly, now with raw, deduped, weighted, independent, and adjusted support plus non-authoritative hints
- the assistant does not choose a winner

This keeps disagreement explicit instead of hiding it behind a synthesized answer.

## Conflict severity

`v0.9.3` keeps the `v0.9.1` severity layer:

- `strong_conflict`: the same entity/property has clearly different asserted values
- `possible_conflict`: the disagreement is real but more overlapping or ambiguous

If there is no conflict, `conflict_flag` stays `false` and `conflict_severity` is `null`.

## Source quality rubric

`v0.9.5` keeps the deterministic `source_quality` label on the visible sources used in conflict evaluation.

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

## Source independence rubric

`v0.9.5` adds a deterministic `source_independence` label to the visible sources and clustered conflict support.

Allowed values:

- `independent`
- `related`
- `duplicate_like`
- `unclear`

The current rubric is intentionally simple and heuristic:

- `duplicate_like`: near-identical phrasing or effectively the same source identity
- `related`: similar wording, same source family, or slight variations that look correlated
- `independent`: clearly different phrasing or evidence clusters supporting the same claim
- `unclear`: not enough similarity signal to classify confidently

This is still not truth determination.
It is an operator-facing correlation hint only.

## Conflict usefulness hints

The new hint fields are intentionally non-authoritative:

- `claim_support_counts_raw`: visible support counts before duplicate suppression
- `claim_support_counts_deduped`: duplicate-aware support counts used for tie handling and confidence
- `claim_weighted_support`: quality-weighted support totals derived from visible sources
- `claim_independent_support`: count of support clusters treated as independent corroboration
- `claim_independence_adjusted_support`: weighted support after correlation discounts are applied inside a cluster
- `dominant_claim_status`: whether one claim is dominant, tied, or still unclear
- `dominant_claim_basis`: whether the dominant hint came from `independence_adjusted_support`, `weighted_support`, `deduped_support`, `tie`, or `unclear`
- `claim_confidence`: a conservative heuristic summary of how separated the weighted or deduped counts are
- `conflict_summary_hint`: a deterministic plain-language summary of the current split evidence
- `most_supported_claim`: a hint that one value has the strongest current dominance basis
- `most_recent_claim`: a hint that one value is newer than the others when source timestamps exist
- `source_quality_breakdown`: a compact summary of how many visible supporting sources landed in each quality bucket
- `source_independence_breakdown`: a compact summary of how much visible support looks independent versus correlated
- `evidence_clusters`: the source groups used to reason about correlation

These fields are for operator inspection only.
They do not change `answer_mode`, and they do not let the assistant collapse a conflict into a single answer.
They are not truth scores and they are not probability estimates.

If support is tied, `most_supported_claim` is omitted.
If timestamps are missing or tied, `most_recent_claim` is omitted.
If stronger weighted support, deduplicated support, and recency point in different directions, `conflict_summary_hint` calls that out explicitly.

## Weighted and independence-adjusted support

`claim_weighted_support` is built from the visible supporting sources for each claim.

The current fixed weights are:

- `low = 1.0`
- `medium = 1.5`
- `high = 2.0`

Weighted support is computed after duplicate suppression.
That means duplicate-like notes remain visible in raw counts but do not multiply the weighted total unfairly.

`claim_independence_adjusted_support` is built after clustering the visible support:

- the first source in a cluster keeps full weight
- additional `related` sources are discounted
- additional `duplicate_like` sources are discounted more aggressively
- separate independent clusters keep full weight

This lets the trust surface distinguish:

- more notes
- better notes
- more independent notes

The dominance logic is conservative:

1. Compare `claim_independence_adjusted_support` first.
2. If one claim is clearly higher, `dominant_claim_status = dominant` and `dominant_claim_basis = independence_adjusted_support`.
3. If adjusted support ties, fall back to `claim_weighted_support`.
4. If weighted support still ties, fall back to `claim_support_counts_deduped`.
5. If all remain tied, `dominant_claim_status = tie` and `dominant_claim_basis = tie`.
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

When a note is retrieved but the support remains weak, the assistant can still return `answer_mode = direct` while marking `grounding.status = weak`.

That means the response can answer cautiously from visible evidence instead of collapsing to the generic fallback message.

The presentation layer now mirrors that trust state without hiding the workflow's caveats:

- `grounded`: the answer pane shows the direct grounded answer, while the rationale layer explains the supporting evidence
- `weak`: the answer pane still shows the direct grounded answer when one exists, while deterministic caveats and `grounding.note` move into `Why this answer`
- unsupported detail prompts still get a direct non-verification answer in the answer pane, while partial-context and retrieval-limit wording remains in `Why this answer`
- `none`: the assistant keeps the existing insufficient-memory fallback in the answer pane and does not synthesize an answer

This keeps weak support visible in the structured response and in the rationale layer without burying the direct answer sentence.
It also keeps clearly unsupported questions from receiving a weakly phrased answer just because a generic history file was nearby in semantic space.
If a user asks for undocumented or not-recorded project mistakes, the answer now explicitly says that repo-visible memory cannot support that claim instead of re-labeling documented failures as undocumented facts.

The retrieval remains inspectable through:

- `retrieved_candidates`
- `grounding`
- `trust`

So operators can see that something partial was found without the assistant overstating confidence.

## Query phrasing and ranking

`v0.9.5` also treats broader history prompts such as `List...`, `Walk me through...`, `Explain...`, and `Summarize...` as fact-seeking queries for ranking purposes.

That keeps the stricter relevance penalties and generic-runtime filtering active even when the user does not phrase the question as `what`, `which`, or `find`.

The lexical side now also avoids counting query-unrelated filepath structure as evidence, and it ignores very short non-numeric lexical terms when building the visible candidate set.
That reduces false-positive retrieval on unsupported questions while keeping anchor-style and history-specific phrasing usable.

For phrasing drift on project-history questions, the assistant now adds a small canonical lexicon when the query clearly asks about:

- failures, problems, issues, bugs, breakdowns, weak points, incidents, regressions, mistakes, or what went wrong
- uncertainty, incompleteness, or what is not documented

This does not hardcode an answer.
It only helps the candidate set keep the intended history-pack files in play when the user changes wording.

## Intent-aware retrieval weighting

The assistant now exposes a bounded failure-intent retrieval bias for ranking, not answering.

When the normalized query clearly asks about:

- failures
- problems
- issues
- bugs
- breakdowns
- regressions
- incidents
- mistakes
- what went wrong
- weak points

the retrieval pipeline marks `is_failure_intent = true` before candidate ranking.

That flag does not bypass trust gates, grounding thresholds, or fallback behavior.
It only changes how closely competing sources are compared.

For failure-intent queries, the ranking layer now gives a small domain boost to candidates whose title, filename, or filepath clearly matches the failures corpus, especially:

- `04-problems-and-failures.txt`
- `inbox/openbrain-history/04-problems-and-failures.txt`

The boost is intentionally small and inspectable:

- it helps the domain-specific failures file outcompete weak generic notes when the candidates are otherwise close
- it does not force inclusion of an irrelevant source
- it does not override a clearly stronger non-failure source on a non-failure query

The visible candidate metadata can now include:

- `is_failure_intent`
- `intent_domain_match`
- `intent_domain_boost`

Those fields are diagnostic only.
They explain why a failure-domain file ranked higher; they do not change the answer rules after retrieval.

## Project Isolation Enforcement

When a request includes `project_slug`, retrieval is now strictly scoped to that project before ranking begins.

For a scoped request such as:

- `project_slug = openbrain-history`

the assistant now only keeps candidates whose stored `project_slug` exactly matches `openbrain-history`.

That enforcement happens in two places:

- the SQL retrieval stage returns project-matching rows only and leaves the `general` and `all` pools empty for scoped requests
- the retrieval assembly stage applies the same exact-slug check again before ranking and again before final source selection

Null, empty, or missing project slugs are excluded from scoped retrieval.
They are not treated as global fallback memory.

This matters because cross-corpus retrieval is unsafe even when the retrieved text is real.
A different project can produce a plausible but misleading answer that crosses the system trust boundary.

Project isolation does not change the trust rules after retrieval:

- `grounding`
- `answer_mode`
- conflict handling
- weak-evidence handling

still behave the same way once the candidate set has been scoped correctly.

That means a scoped query can still return `grounding.status = weak` if the matching project contains only limited evidence.
The isolation fix guarantees scope integrity, not stronger evidence than the project actually contains.

## Relevance Threshold And Fallback Behavior

The assistant now applies an answer-eligibility gate after retrieval ranking and before answer generation.

This gate is intentionally narrow.
It does not replace the normal trust model, and it does not suppress valid weak-history answers just because their similarity is low.

The fallback triggers when a scoped candidate set still looks irrelevant overall, for example when:

- the top similarity stays below the answer-eligibility floor
- lexical overlap is minimal
- there is no domain or intent match
- there are no strong token, anchor, entity, or structured signals
- only a tiny answer set would be selected

When that happens, the assistant does not carry the weak match into answer generation.
It returns the existing insufficient-memory fallback instead:

- `answer_mode = insufficient`
- `grounding.status = none`
- `selected_sources = []`

The current gate is designed to preserve real weak answers.
It explicitly allows the normal weak path when the query still has meaningful support signals such as:

- uncertainty-history intent
- failure-domain intent
- anchor or title hits
- strong or structured token hits
- multiple compatible supporting sources

This keeps the distinction clear:

- `weak`: relevant but incomplete project evidence exists
- `none`: the retrieved candidates are too weak or too off-topic to justify an answer

## Answer Quality Guard

The assistant now applies a final answer-quality guard before returning weak or boundary-case answers.

This guard does not change retrieval, ranking, project isolation, conflict handling, or the insufficient-memory fallback.
It only rewrites the final answer text when the retrieved evidence is real but the raw model output drifts into generic assistant filler.

What the guard removes:

- assistant identity language such as `I'm CrispyBrain` or `as an AI`
- generic scope disclaimers such as `I don't have information outside...`
- low-value meta lead-ins such as `Based on the retrieved memory context, here's what I found`

What the guard keeps:

- repo-visible facts that were actually retrieved
- weak-grounding uncertainty notes
- explicit statements about what the stored project memory cannot verify

For weak and sparse answers, the returned text now uses an adaptive project-grounded structure:

- structured mode when multiple meaningful supported facts exist:
  - what is known
  - what is uncertain
  - what cannot be verified
- narrative mode when facts are sparse or only lightly supported:
  - a short paragraph for the supported details
  - one concise limitation sentence
  - one concise non-verification sentence

This means:

- `grounding.status = weak` still returns a cautious direct answer when the query is on-topic
- `grounding.status = none` still uses the unchanged insufficient-memory fallback
- boundary prompts such as `not in the project memory` no longer leak assistant identity language into the answer

## Answer Conciseness Guard

The final weak-answer formatter now also compresses presentation so the answer stays short and non-repetitive.

What changed:

- the refinement guard now chooses between:
  - structured mode for answers with multiple meaningful supported facts
  - narrative mode for sparse or low-information answers
- section headers are omitted in narrative mode so weak answers do not show empty or mechanical blocks
- the refinement guard parses supported facts, uncertainty, and non-verification separately instead of wrapping the raw model answer as one large "known" block
- contradiction-style lead-ins such as `no information is available` are removed when supported facts are present elsewhere in the answer
- low-value generic "known" lines are dropped in favor of stronger retrieved facts or a tighter source-scope summary
- repeated uncertainty lines are collapsed into a single limitation paragraph
- bullet-heavy weak summaries are compacted into a shorter prose summary when possible
- meta-justification language such as `as per my training`, `I'm hesitant to`, `I should only`, `I will refrain`, `I cannot provide`, or `this appears to be self-referential` is stripped from the final answer

What did not change:

- retrieval, ranking, isolation, trust, and fallback logic
- grounded answers
- conflict answers
- the insufficient-memory fallback

The trace still carries the richer trust and eligibility details.
The answer surface now keeps only the concise project-grounded summary.

For runtime inspection, the trace can now also show:

- `synthesis_refined`
- `contradiction_phrase_removed`
- `repeated_uncertainty_collapsed`

## Output Sanitization

The final answer layer now also applies a user-facing sanitization pass after structure selection.

This pass does not change retrieval, ranking, adaptive structure, trust, fallback behavior, or factual scope.
It only cleans the returned wording so the visible answer reads like a natural summary instead of an internal system artifact.

What the sanitization removes or normalizes:

- internal identifiers such as `cb-v...`, `cbv...`, chunk labels, and path-like strings
- operator or debug phrasing such as `operators should inspect...`, `check selected sources...`, or `refer to memory IDs...`
- template residue such as `Based on the retrieved memory context`
- fragmented semicolon chains in narrative answers

What the sanitization preserves:

- supported facts
- uncertainty
- explicit non-verification
- structured mode versus narrative mode

This means the answer text is cleaner for end users, while the trace and response metadata still expose the operator-facing details needed for validation.

## Memory-Only Answer Enforcement

The assistant now applies a stricter memory-only containment layer before returning the final answer.

What changed:

- the answer-generation prompt now explicitly requires the model to answer only from the retrieved memory context
- the prompt now explicitly forbids training data, general knowledge, assumptions, speculation, rumors, and invented facts
- if a detail is not directly supported by the retrieved memory context, the model is told to say that it cannot be verified from project memory
- the final answer scrubber now removes training-data and general-knowledge phrasing if it appears anyway
- the response layer no longer injects a hardcoded CrispyBrain fact outside the retrieved memory context

What is blocked:

- phrases such as `based on my training`, `based on training data`, `based on general knowledge`, `generally speaking`, `it is known that`, `rumored`, and `in general`
- answer text that tries to fill gaps with model priors instead of retrieved evidence

What happens instead:

- when retrieved sources support an answer, the response stays inside those visible notes
- when the history is partial, the answer remains cautious and uncertainty-aware
- when a requested detail is missing from the retrieved notes, the answer explicitly says it cannot be verified from project memory

What did not change:

- retrieval, ranking, intent weighting, project isolation, and relevance threshold behavior
- weak-answer synthesis, conflict handling, and the insufficient-memory fallback

The containment goal is strict but simple: every final answer sentence should now come from retrieved project memory or from an explicit statement that the memory cannot verify the missing detail.

## Uncertainty versus conflict

The assistant now separates incomplete history from true contradiction more explicitly.

- `answer_mode = direct` with `grounding.status = weak` is used when the retrieved notes are compatible but partial, incomplete, or differently scoped
- `answer_mode = conflict` is reserved for mutually exclusive claims that cannot both be true
- generic absence-style statements such as different notes saying something is not fully documented no longer count as a contradiction by themselves

For uncertainty-focused questions, the answer now stays on the direct synthesis path and explains:

- what the repo does support
- what remains incomplete or not explicitly documented
- that the evidence is limited
