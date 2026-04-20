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
