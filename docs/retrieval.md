# Retrieval

## v0.9.4 calibration

`v0.9.4` keeps the existing `assistant` retrieval path and the `v0.9.1` calibration layer on top of `v0.9`:

- short factual notes get a ranking boost instead of being filtered out as low-signal by default
- lexical fallback candidates are collected alongside semantic candidates for identifiers, anchors, codes, and sparse factual queries
- the retrieval stage preserves a slightly wider competing set so the answer layer can see agreement or disagreement instead of collapsing too early
- obviously generic runtime/build-context notes can be trimmed back out of factual candidate lists before final answer selection
- a lightweight entity/topic focus can boost clearly on-topic notes and trim off-topic generic noise when the query names a subject

`v0.9.4` does not redesign retrieval further.
Its main follow-on work is still in the answer layer: the preserved conflicting candidates now carry enough grouped source support, duplicate-aware support identities, source-quality labels, and recency metadata for the trust surface to expose better hints.

## Short-note boost

The retrieval assembler now adds a small boost for:

- short notes with dense factual signal
- notes with structured tokens such as anchors, filenames, IDs, or protocol codes
- notes whose signal density is high relative to word count

This does not remove the existing similarity-led ordering.
It only keeps short, specific notes from being drowned out by longer chunks.

## Lexical fallback

The `Retrieve Candidate Memories` node now returns:

- semantic candidate arrays
- lexical candidate arrays

The lexical side is intentionally simple:

- lowercased `LIKE` matching across title, content, filename, and filepath
- query terms from the normalized request
- stronger token matching for anchors, filenames, and identifier-style terms

The assistant turns lexical fallback on when:

- the query already looks anchor-like
- the query includes strong tokens such as IDs or codes
- the semantic preview is weak or sparse

The merged candidate pool is then rescored in the existing retrieval assembler.

## Candidate preservation

`v0.9` keeps more close competitors alive by:

- increasing the semantic candidate window
- keeping a small lexical candidate window
- preserving extra nearby candidates when their ranking scores are close or when they carry strong lexical evidence

That preservation is what enables:

- generalized answers across multiple notes
- conflict detection when multiple retrieved notes disagree

## Candidate trimming

`v0.9.1` adds a conservative cleanup pass after raw candidate scoring, and `v0.9.3` keeps that behavior.

It does not redesign retrieval and it does not remove lexical fallback.
Instead it only trims candidates when all of these are true:

- the query looks factual or entity-focused
- the note looks like generic runtime/build-context noise from filename/title heuristics
- the note does not match the inferred entity/topic focus strongly enough to stay visible

The main goal is to keep `retrieved_candidates` readable in the demo and trust output.

Examples of notes that can now be trimmed more aggressively:

- `build-context-*`
- `runtime-fix-*`
- generic local runtime/test notes with protocol-like words but no real subject match

## Entity / topic focus

When the query exposes a simple subject/property shape such as:

- `What protocol does Alpha system use?`
- `How does the delta guide improve retrieval for ids?`
- `What is the beacon protocol?`

the assistant now infers a small `entity_focus` object.

That focus is used to:

- boost notes that clearly mention the named subject
- keep property-only generic notes from crowding the visible candidate list
- stay conservative enough that anchor lookup and lexical fallback still work

## Limitations

The calibration layer is intentionally heuristic.

Non-goals:

- full entity linking
- ontology-driven topic classification
- hard truth ranking between conflicting notes
- aggressive filtering that could hide legitimate competing evidence

## Conflict detection input

Conflict detection is intentionally heuristic and answer-layer driven.

The retrieval stage provides enough context for that by preserving:

- multiple relevant candidates
- source metadata
- lexical and structured-token diagnostics

The answer layer then checks those retrieved notes for incompatible claims instead of guessing.
In `v0.9.4`, that preserved evidence is also used to compute duplicate-aware support counts, source-quality labels, weighted support, and weighted-vs-deduped dominance handling without changing retrieval itself.
