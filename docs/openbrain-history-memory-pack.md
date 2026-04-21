# OpenBrain History Memory Pack

## Purpose

This document audits the historical memory pack created for self-query ingest. The pack is a curated historical corpus derived from repo-visible evidence, not a perfect transcript of every conversation, experiment, or decision that happened outside the repository.

## Location Of The Generated Ingest Files

The generated plain-text files live at:

```text
/Users/elric/repos/crispybrain/inbox/openbrain-history/
```

In repo-relative form, that is:

```text
inbox/openbrain-history/
```

Because the canonical inbox convention is `inbox/<project-slug>/`, the effective project slug for retrieval is `openbrain-history`.

## File Inventory

- `01-project-origin.txt`
- `02-timeline-v0.1-to-v0.95.txt`
- `03-architecture-decisions.txt`
- `04-problems-and-failures.txt`
- `05-adopted-vs-deferred-features.txt`
- `06-testing-and-validation-history.txt`
- `07-operator-notes.txt`
- `08-current-state-v0.95.txt`
- `09-glossary-and-project-names.txt`

## What The Memory Pack Contains

The pack is organized for retrieval quality rather than narrative polish. It captures:

- the earliest repo-visible origin framing
- the phase-by-phase timeline from partially documented early OpenBrain work through CrispyBrain `v0.9.5`
- major architecture decisions and their evidence level
- real documented problems, failures, and unresolved limits
- adopted versus deferred features
- validation and test history
- operator habits and source-of-truth discipline
- a careful current-state snapshot around `v0.9.5`
- glossary and naming clarification for OpenBrain versus CrispyBrain

## Source-Of-Truth Policy

This pack is intentionally restricted to repo-visible evidence. Sources used for curation were:

- [README.md](/Users/elric/repos/crispybrain/README.md)
- [docs/HISTORY.md](/Users/elric/repos/crispybrain/docs/HISTORY.md)
- version notes:
  [docs/crispybrain-v0.4.md](/Users/elric/repos/crispybrain/docs/crispybrain-v0.4.md),
  [docs/crispybrain-v0_5.md](/Users/elric/repos/crispybrain/docs/crispybrain-v0_5.md),
  [docs/crispybrain-v0_5_1.md](/Users/elric/repos/crispybrain/docs/crispybrain-v0_5_1.md),
  [docs/crispybrain-v0_5_2.md](/Users/elric/repos/crispybrain/docs/crispybrain-v0_5_2.md),
  [docs/crispybrain-v0_6.md](/Users/elric/repos/crispybrain/docs/crispybrain-v0_6.md),
  [docs/crispybrain-v0_7.md](/Users/elric/repos/crispybrain/docs/crispybrain-v0_7.md),
  [docs/crispybrain-v0_8.md](/Users/elric/repos/crispybrain/docs/crispybrain-v0_8.md)
- operating and architecture docs:
  [docs/retrieval.md](/Users/elric/repos/crispybrain/docs/retrieval.md),
  [docs/trust-output.md](/Users/elric/repos/crispybrain/docs/trust-output.md),
  [docs/observability.md](/Users/elric/repos/crispybrain/docs/observability.md),
  [docs/operator-quickstart.md](/Users/elric/repos/crispybrain/docs/operator-quickstart.md),
  [docs/demo-local.md](/Users/elric/repos/crispybrain/docs/demo-local.md),
  [docs/ingest-text.md](/Users/elric/repos/crispybrain/docs/ingest-text.md),
  [docs/workflow-sync.md](/Users/elric/repos/crispybrain/docs/workflow-sync.md),
  [docs/setup-minimal.md](/Users/elric/repos/crispybrain/docs/setup-minimal.md),
  [docs/public-release-recommendation.md](/Users/elric/repos/crispybrain/docs/public-release-recommendation.md),
  [docs/public-scope.md](/Users/elric/repos/crispybrain/docs/public-scope.md),
  [docs/open-source-readiness-audit.md](/Users/elric/repos/crispybrain/docs/open-source-readiness-audit.md),
  [docs/legacy-naming-debt.md](/Users/elric/repos/crispybrain/docs/legacy-naming-debt.md),
  [docs/MIGRATION.md](/Users/elric/repos/crispybrain/docs/MIGRATION.md)
- versioned validation scripts under [scripts/](/Users/elric/repos/crispybrain/scripts)
- evaluation seeds under [seed-data/](/Users/elric/repos/crispybrain/seed-data)
- repo-visible git history and commit messages

No private chat history, memory, UI assumptions, or undocumented commit intent was treated as source material.

## Confidence / Limitations

The pack intentionally uses confidence markers such as:

- `Confirmed by README`
- `Confirmed by docs`
- `Supported by git history`
- `Inference from repo context`
- `Not explicitly documented`

Known limits:

- there is no fully documented `v0.1` design note in the repo, so the earliest phase is marked as partial
- the pre-`v0.4` timeline is more dependent on commit history than on polished release notes
- `v0.9.x` evolution is strongly supported by commit messages, eval seeds, README notes, and test harnesses, but not by one single long-form history document
- the pack reflects repo-visible state only; it is not a claim that every real-world decision or conversation has been preserved

## Validation Pass (v0.95 consistency and grounding)

This refinement pass checked the full memory pack for:

- version consistency between `v0.95` task wording and `v0.9.5` repo wording
- repeated facts that were making multiple files sound more alike than necessary
- evidence-label consistency across confirmed facts, git-supported history, and inference
- timeline, architecture, problems, testing, and current-state alignment
- retrieval-friendly headings and shorter section openings

What was fixed:

- normalized body text to `v0.9.5` where the repo provides a documented version string
- added explicit version notes to the timeline, current-state, and glossary files
- kept the existing `v0.95` filenames for task compatibility instead of renaming files
- standardized several `Inference from repo context` labels
- tightened a few validation lines so later `v0.9.x` phases cite scripts or seed files more explicitly

Version normalization decision:

- use `v0.9.5` in prose because that is the dominant repo-visible version spelling
- keep `v0.95` only where the task fixed the filename or where a retrieval query may still use that wording

Remaining ambiguity:

- the repo does not document `v0.95` as a canonical release tag
- the task wording may use `v0.95` as shorthand for `v0.9.5`, but the pack does not upgrade that shorthand into a repo-confirmed fact

## Runtime Validation Loop (2026-04-20)

This end-to-end validation pass checked the real local ingest and assistant path, not just the text files on disk.

What was verified:

- the canonical project slug for this pack is `openbrain-history`
- the local inbox mount exposes `inbox/openbrain-history/` to the n8n container
- the assistant retrieves this pack only after `ingest` is active and the files have actually been stored in `memories`

What was fixed in the runtime path:

- `ingest` had to be active in n8n before the watcher handoff could succeed
- `auto-ingest-watch` needed a payload fix so each discovered file is forwarded from its own current path content instead of risking repeated first-file content during multi-file ingest
- `assistant` needed a weak-grounding fix so broad history queries with reviewed supporting sources return cautious grounded answers instead of the generic insufficient-memory failure
- `ingest` now auto-marks this repo-controlled `openbrain-history` corpus as `reviewed` when the ingest request carries the matching project slug and trusted repo inbox filepath, so the pack does not require manual review promotion after clean re-ingest

What was validated after those fixes:

- failures, problems, bugs, and issues prompts retrieve and select `04-problems-and-failures.txt` instead of substituting a more generic history file
- broad history prompts such as `List...` and `Walk me through...` are treated as fact-seeking retrieval requests for ranking purposes
- weakly grounded answers now include the grounding warning in the answer text itself instead of only exposing it through trace metadata
- clearly unsupported questions no longer borrow cross-project notes when the request is scoped to `openbrain-history`, even though weak same-project matches can still surface under the current grounding rules
- adversarial prompts asking for undocumented mistakes now return an explicit lack-of-evidence answer instead of turning documented failures into new claims
- the failures file now includes a retrieval-wording note so phrasing variants such as `issues`, `bugs`, `breakdowns`, `regressions`, `weak points`, and `went wrong` stay attached to the same repo-supported corpus without adding new historical claims
- uncertainty prompts now stay on a weak direct-synthesis path when multiple sources are compatible but incomplete, instead of flipping into conflict mode just because different notes describe different missing pieces
- low-signal off-topic prompts now fall back instead of turning a single weak semantic match into a misleading `weak` answer

## Failure-domain retrieval weighting (2026-04-21)

This follow-up refinement addressed a proven ranking failure mode: weak generic notes could occasionally compete too well against the actual failures corpus on development-failure questions.

What changed in the runtime:

- the assistant now detects failure intent from normalized query wording such as `failures`, `problems`, `issues`, `bugs`, `went wrong`, `breakdowns`, `regressions`, `incidents`, `mistakes`, and `weak points`
- when that flag is active, retrieval gives a small domain boost to clearly matching failures sources, especially `04-problems-and-failures.txt`
- the boost is used only during ranking and close-candidate tie-breaks

Why this matters:

- the failures corpus is the repo-visible source that actually documents breakdowns and negative outcomes
- generic notes about principles, evaluation, or current state may still be relevant context, but they should not outrank the purpose-built failures file on a failure query just because they look cleaner or more independent

What did not change:

- no answers are hardcoded
- grounding still determines whether the answer is `grounded`, `weak`, or `none`
- unsupported questions still fall back or stay explicitly limited
- non-failure prompts such as uncertainty or version-difference queries do not receive this domain boost

The intended effect is narrow and practical:

- failure-domain prompts should now keep `04-problems-and-failures.txt` in `selected_sources` when it is actually relevant
- trust remains conservative because source selection and answer confidence are still evaluated separately

## Project Isolation Enforcement (2026-04-21)

This follow-up integrity fix enforces strict project-level memory isolation for scoped queries.

What changed in the runtime:

- when a request includes `project_slug = openbrain-history`, retrieval now keeps only memories whose stored `project_slug` is exactly `openbrain-history`
- the project filter runs before ranking, lexical scoring, intent weighting, or answer selection
- `general`, `all`, `lexical_general`, and `lexical_all` pools stay empty for scoped requests
- a defensive same-slug check is applied again before final source selection

What is excluded:

- rows from other projects such as `alpha` or live-demo corpora
- rows with null, empty, or missing `project_slug`
- any cross-corpus fallback that would mix unrelated memory packs into a scoped answer

Why this matters:

- cross-project retrieval can sound plausible while still being wrong for the requested corpus
- for this history pack, the integrity boundary is part of the trust model, not just a retrieval preference

What did not change:

- failure-intent weighting still works inside the scoped corpus
- grounding, weak-evidence notes, uncertainty handling, and conflict behavior are unchanged
- strict isolation does not guarantee a `none` result; weak same-project evidence can still produce a cautious `weak` answer if that is what the scoped corpus supports

## Relevance Threshold And Fallback Behavior (2026-04-21)

This follow-up correctness fix adds a narrow answer-eligibility gate for irrelevant queries.

What changed in the runtime:

- retrieval candidates are still ranked and exposed for inspection
- but before answer generation, the assistant now checks whether the final answer set is too weak and too off-topic to justify a response
- low-signal single-source matches now fall back instead of becoming `answer_mode = direct` with `grounding.status = weak`

The gate is designed around existing retrieval signals, including:

- top similarity
- lexical overlap
- strong token hits
- anchor or title hits
- intent-domain matches
- final selected-source count

What now falls back:

- irrelevant prompts such as developer food habits
- unrelated prompts like the earlier `moonbase` test case
- other cases where the history pack only offers a weak semantic neighbor without meaningful topical support

What still stays weak instead of falling back:

- uncertainty questions that genuinely map to incomplete project history
- narrow but real history prompts that still have meaningful lexical or intent support
- failure-domain prompts that match the documented failures corpus

The goal is conservative:

- block truly irrelevant weak matches
- keep valid weak-history answers
- preserve the existing trust surface instead of hiding retrieval state

## Answer Quality Guard (2026-04-21)

This final polish pass improves weak-answer usefulness without changing retrieval, ranking, isolation, or fallback decisions.

What changed in the runtime:

- weak or boundary-case answers now pass through an answer-quality guard before the final response is returned
- generic assistant filler such as `I'm CrispyBrain`, `I don't have information outside...`, and `as an AI` is stripped from the final answer text
- generic lead-ins such as `Based on the retrieved memory context, here's what I found` are removed when the answer is being rewritten
- weak answers are reformatted into a domain-grounded structure that explains:
  - what the retrieved memory does support
  - what remains uncertain or incomplete
  - what the stored project memory cannot verify

What did not change:

- the insufficient-memory fallback remains the same when no usable evidence is selected
- uncertainty synthesis still stays on the weak direct-answer path when the project history is genuinely incomplete
- failure-domain and other grounded answers still use the existing ranking and trust path

Validated result:

- boundary prompts such as `Tell me something about CrispyBrain that is not in the project memory` now stay inside the repo-visible domain instead of leaking assistant-identity filler
- weak uncertainty prompts still answer meaningfully, but now make the limitation and non-verifiable edge explicit in the answer text

## Answer Conciseness Guard (2026-04-21)

This final UX pass keeps the same weak-answer honesty while making the wording shorter and less defensive.

What changed in the runtime:

- weak and sparse answers now use adaptive answer structure:
  - structured mode when the selected evidence supports multiple meaningful facts
  - narrative mode when the answer is sparse, lightly supported, or otherwise too thin for clean section blocks
- narrative mode removes section headers entirely, so low-information answers do not show empty `known / uncertain / cannot verify` shells
- the refinement guard separates supported facts, uncertainty, and non-verification before rewriting, so supported facts do not get mixed back together with uncertainty or non-verification lines
- contradiction phrasing such as `no information is available` is removed when the same answer already contains supported facts
- low-value generic "known" filler is dropped when stronger project-supported details are available
- repeated uncertainty wording is collapsed so the answer does not restate the same limitation multiple times
- meta-reasoning and self-justification phrases such as `as per my training`, `I'm hesitant to`, `I should only`, `I will refrain`, `I cannot provide`, and `this appears to be self-referential` are stripped from the final answer
- weak bullet lists are compacted into shorter prose where that keeps the answer easier to scan

What did not change:

- retrieval, ranking, project isolation, trust, and fallback behavior
- grounded answers and conflict answers
- the insufficient-memory fallback when no usable evidence is selected

Validated result:

- weak answers stay domain-grounded and uncertainty-aware
- the wording is shorter, less repetitive, and more professional for first-time users
- sparse development-history answers now fall back to narrative mode instead of forcing empty sections
- trace inspection can now confirm the refinement pass through `synthesis_refined`, `answer_structure_mode`, `supported_fact_count`, `meaningful_source_count`, `contradiction_phrase_removed`, and `repeated_uncertainty_collapsed`

## Memory-Only Answer Enforcement (2026-04-21)

This final containment pass tightens the assistant so answers stay strictly inside retrieved project memory.

What changed in the runtime:

- the final answer-generation prompt now explicitly requires memory-only answering
- the prompt now explicitly forbids training data, general knowledge, assumptions, speculation, rumors, and invented facts
- if the requested detail is not directly supported by the retrieved notes, the assistant is instructed to say it cannot be verified from project memory
- the final answer scrubber now removes training-data and general-knowledge leakage if it appears anyway
- the response formatter no longer injects a hardcoded CrispyBrain fact outside the retrieved memory context

What this means for this memory pack:

- answers about `openbrain-history` should now be traceable to the selected `openbrain-history` sources or to an explicit non-verification statement
- open-ended or boundary prompts should stay inside the retrieved note set instead of drifting into model priors
- weak answers remain allowed when the pack has partial evidence, but they must still stay memory-grounded

What did not change:

- retrieval weighting
- project isolation
- relevance-threshold fallback behavior
- uncertainty synthesis and conflict handling
- the existing insufficient-memory fallback when no usable memory is selected

Validated result:

- boundary prompts no longer depend on assistant self-knowledge or training-data language
- final answers either stay inside the retrieved history notes or explicitly say the missing detail cannot be verified from project memory

Operational note:

- if `openbrain-history` rows already exist from an earlier broken watcher pass, clear those rows and re-ingest the pack after re-importing the updated watcher workflow

## How To Use The Memory Pack In The Lab

1. Ensure the local ingest/watch path is active in the lab runtime.
2. Leave the files in `inbox/openbrain-history/`.
3. Trigger or wait for `auto-ingest-watch`, depending on the local setup.
4. Query using project slug `openbrain-history`.
5. Ask history-oriented prompts such as:
   - `What is OpenBrain and how did it evolve into CrispyBrain?`
   - `What problems were encountered during development?`
   - `Why were some features adopted and others deferred?`
   - `What was the state of the project at v0.95?`
6. Inspect whether answers cite the history pack content rather than generic invention.

## Naming Transition Note

Repo evidence supports a real naming transition inside this repository:

- early repo history uses OpenBrain-era names
- `v0.4` is the first public-facing CrispyBrain release line
- [docs/MIGRATION.md](/Users/elric/repos/crispybrain/docs/MIGRATION.md) records workflow, webhook, folder, and localStorage migration from `openbrain-*` names
- [docs/legacy-naming-debt.md](/Users/elric/repos/crispybrain/docs/legacy-naming-debt.md) records remaining compatibility debt such as `openbrain_chat_turns`

The README attribution also separately states that CrispyBrain was inspired by Nate's OpenBrain work. The memory pack keeps those two facts distinct:

- external inspiration
- internal repo naming lineage

## Statement Of Scope

This memory pack is a curated historical corpus derived from repo-visible evidence. It is meant to improve grounded self-query behavior for CrispyBrain/OpenBrain history questions. It should not be treated as a perfect transcript of all project conversations or a complete record of every undocumented decision.
