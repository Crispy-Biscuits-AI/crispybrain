# Retrieval

## v0.9 changes

`v0.9` keeps the existing `assistant` retrieval path and extends it in three narrow ways:

- short factual notes get a ranking boost instead of being filtered out as low-signal by default
- lexical fallback candidates are collected alongside semantic candidates for identifiers, anchors, codes, and sparse factual queries
- the retrieval stage preserves a slightly wider competing set so the answer layer can see agreement or disagreement instead of collapsing too early

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

## Conflict detection input

Conflict detection is intentionally heuristic and answer-layer driven.

The retrieval stage provides enough context for that by preserving:

- multiple relevant candidates
- source metadata
- lexical and structured-token diagnostics

The answer layer then checks those retrieved notes for incompatible claims instead of guessing.
