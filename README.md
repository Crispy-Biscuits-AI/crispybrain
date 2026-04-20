<p align="center">
  <img src="assets/crispybrain-biscuit.png" alt="CrispyBrain tea biscuit" width="220">
</p>

<h1 align="center">CrispyBrain</h1>

<p align="center">
  CrispyBrain is a local-first, self-hosted memory system that exposes what it knows, how it knows it, and where it conflicts — instead of pretending to produce a single correct answer.
</p>

`crispybrain` is the public product repo for CrispyBrain: an open-source memory, retrieval, and agent lab built around real workflow exports and a real local UI path.

It is the place to understand the current browser surface, the workflow shape, and the local runtime path that ends at `http://localhost:8787` when run through the sibling `crispy-ai-lab` repo.

## <img src="assets/biscuit-emoji.png" width="18" /> Latest Capabilities

CrispyBrain currently provides:

- Evidence-aware retrieval (not just semantic similarity)
- Conflict detection with explicit non-collapse behavior
- Source quality weighting (not all notes count equally)
- Independence-aware reasoning (distinguishes repeated vs independent evidence)
- Correlation handling (duplicate-heavy signals are discounted)
- Structured trust output (inspectable reasoning surface)
- Deterministic evaluation system (tests match live behavior)

## <img src="assets/biscuit-emoji.png" width="18" /> What This Is Not

CrispyBrain is not:
- a chatbot
- a knowledge base
- a system that “just remembers everything”

It is a system that models evidence, conflict, and uncertainty explicitly.

## <img src="assets/biscuit-emoji.png" width="18" /> Start Here

- [Local UI](docs/demo-local.md)
- [Ingest data](docs/ingest-text.md)
- [Operator tools](docs/operator-quickstart.md)

## Current Status (v0.9.5)

CrispyBrain is a working local-first memory and retrieval system with:

- semantic + lexical retrieval
- conflict detection (no forced answers)
- support counts (raw + deduplicated)
- weighted support (source quality)
- independence-aware reasoning (correlation handling)
- structured trust output (exposes evidence and uncertainty)
- deterministic evaluation harness aligned with runtime behavior

## <img src="assets/biscuit-emoji.png" width="18" /> Why CrispyBrain Exists

CrispyBrain exists to make a local memory-backed assistant path visible and inspectable instead of magical.

The repo is intentionally honest about the current slice:

- a real browser UI
- a real n8n orchestration path
- grounded retrieval instead of mocked answers
- operator-facing inspection tools for memory quality

## <img src="assets/biscuit-emoji.png" width="18" /> What It Can Do Today

Today’s checked-in repo surface can:

- run a real local UI flow through `crispybrain-demo` and `assistant`
- retrieve memory-backed answers instead of static placeholder text
- answer exact note-name and strong anchor-style note lookups deterministically
- handle generalized questions across one or more agreeing notes more reliably
- surface conflicting stored notes explicitly instead of guessing
- classify conflicts as `strong_conflict` or `possible_conflict`
- show per-claim support counts plus most-supported and most-recent conflict hints
- expose dominant/tie status, duplicate-aware support counts, weighted support, independence-adjusted support, dominant basis, heuristic conflict confidence, and a summary hint
- attach deterministic source-quality labels to visible conflict sources
- attach deterministic source-independence labels and evidence clusters to visible conflict sources
- keep factual candidate lists cleaner when generic runtime/build-context notes are off-topic
- expose trust and source metadata in responses
- expose grounding status, supporting-source counts, and visible evidence fields in the browser path
- let operators inspect memory quality by project
- export suspect rows and snapshot health over time
- update review state for stored memory rows through the memory inspector
- run the repo-tracked `v0.9.5` independence-aware evaluation pack with compact diagnostics

## High-Level Architecture

The current public path is intentionally small but real:

```text
browser
-> localhost:8787
-> /api/demo/ask
-> n8n crispybrain-demo
-> assistant
-> retrieval + grounded answer
```

The main runtime lives in the sibling `crispy-ai-lab` repo.
This repo provides the checked-in workflow exports, docs, and public-facing product surface for that lab runtime.
The canonical ingest inbox for CrispyBrain is now the repo-owned path `inbox/<project-slug>/`, which resolves locally to `/Users/elric/repos/crispybrain/inbox/<project-slug>/`.

## Repository Structure

- `demo/`: the current browser UI and local proxy server
- `workflows/`: exported n8n workflow JSON, including `assistant` and `crispybrain-demo`
- `sql/`: checked-in SQL needed by the current assistant path
- `scripts/`: maintainer and local helper scripts
- `docs/`: setup, UI, scope, and technical notes
- `assets/`: public artwork used by the UI and docs

## Canonical n8n Runtime

The canonical CrispyBrain entrypoint set is:

- required: `assistant`
- required: `ingest`
- required: `crispybrain-demo`
- optional: `auto-ingest-watch`

Current retired duplicate in the audited local n8n runtime:

- `crispybrain-auto-ingest-watch`, now inactive in `Personal -> CrispyBrain Archive`
- `crispybrain-assistant`, now inactive in `Personal -> CrispyBrain Archive`
- `crispybrain-ingest`, now inactive in `Personal -> CrispyBrain Archive`

If you organize them into folders in n8n, the recommended home is `Personal -> CrispyBrain`.

Folder placement is organizational only. What is actually live is determined by the workflow `active` state and the webhook or trigger path that your caller hits.

Canonical public webhooks after the hard cutover are:

- `POST /webhook/assistant`
- `POST /webhook/ingest`
- `POST /webhook/crispybrain-demo`

Any remaining client still calling `POST /webhook/crispybrain-assistant` or `POST /webhook/crispybrain-ingest` must be updated.

The canonical watcher workflow is now `auto-ingest-watch`, and it is wired to call `POST /webhook/ingest`.

The current verified local lab runtime now mounts the repo inbox directly:

- host source: `/Users/elric/repos/crispybrain/inbox`
- container target: `/home/node/.n8n-files/crispybrain/inbox`
- `auto-ingest-watch` polls that canonical inbox and hands new `.txt` files to `POST /webhook/ingest`
- a real file drop into `/Users/elric/repos/crispybrain/inbox/alpha/` was ingested and retrieved through `POST /webhook/assistant`

Today’s verified UI path is:

- `crispybrain-demo` -> `assistant`

## Getting Started

The most believable local path uses this repo and `crispy-ai-lab` together.

1. Clone both repos as sibling directories.

```bash
git clone <crispybrain-repo-url> crispybrain
git clone <crispy-ai-lab-repo-url> crispy-ai-lab
```

2. Configure and start the lab runtime.

```bash
cd crispy-ai-lab
cp .env.example .env
docker compose up -d postgres n8n crispybrain-demo-ui
```

3. Import the current workflow set from this repo into the running n8n container.

```bash
WORKFLOW_DIR=../crispybrain/workflows \
CONFIRM_IMPORT=I_UNDERSTAND \
scripts/workflows/import-exported-into-docker.sh
```

4. In n8n, create a Postgres credential named `Postgres account`, then activate `assistant`, `ingest`, and `crispybrain-demo`. Activate `auto-ingest-watch` only if your local runtime is actually wired to use it.

5. Create the repo-owned inbox folder you want to ingest from, for example `mkdir -p /Users/elric/repos/crispybrain/inbox/alpha`, and place plain text notes under that project folder.

6. Open the local UI at `http://localhost:8787`.

7. Use:

- project slug: `alpha`
- question: `How am I planning to build CrispyBrain?`

Success currently looks like:

- the page loads on `localhost:8787`
- the theme selector is available
- the response includes an answer, sources, and traceable retrieval state
- the trace panel shows execution and retrieval signals without depending on every backend field being present

## UI, Workflow, Ingestion, and Operator Entry Points

Use these docs as the next stop depending on what you want to do:

- [Local UI](docs/demo-local.md): run the `8787` UI path and verify the UI/workflow flow
- [Operator Quickstart](docs/operator-quickstart.md): get the fastest realistic operator setup
- [Ingesting Text](docs/ingest-text.md): drop plain text into the current ingest path safely
- [Workflow Sync](docs/workflow-sync.md): keep checked-in workflow exports aligned with n8n
- [CrispyBrain v0.8](docs/crispybrain-v0_8.md): trust and evaluation release notes, grounding behavior, and the 8-case harness
- [Retrieval Notes](docs/retrieval.md): the v0.9.5 short-note, lexical fallback, candidate-trimming, and correlation-aware trust-layer behavior
- [Trust Output](docs/trust-output.md): `answer_mode`, source quality, source independence, weighted support, dominant basis, and candidate/source interpretation
- [CrispyBrain v0.7](docs/crispybrain-v0_7.md): anchor-aware deterministic retrieval, harness coverage, and validation notes
- [CrispyBrain v0.6](docs/crispybrain-v0_6.md): release summary, runtime validation notes, and known limitations

## <img src="assets/biscuit-emoji.png" width="18" /> Memory Quality and Trust

`v0.6` introduced the first real quality-and-control layer in the public repo.
`v0.7.1` keeps that layer in place and makes retrieval policy explicit.
`v0.8` adds clearer operator-visible grounding and a repeatable evaluation pack.
`v0.9.5` keeps the same workflow shape while adding source independence, evidence clustering, source-quality weighting, and correlation-aware support hints without weakening strict conflict handling.

That includes:

- project memory health visibility
- source quality indicators in assistant and browser responses
- source independence and evidence-cluster metadata on visible conflict sources
- operator control through the upgraded memory inspector
- suspect review/export workflows
- file-based metrics snapshots over time

The main `v0.6` lesson is worth keeping explicit:

- retrieval ranking and metadata correctness are separate concerns

`v0.7.1` narrows that ambiguity instead of pretending it disappeared:

- strong lexical anchors switch retrieval into a conservative anchor mode
- anchor mode prefers stronger title/token matches, then reviewed rows, then `created_at DESC`, then `id DESC`
- non-anchor questions stay on the semantic path
- semantic retrieval remains project-first and similarity-driven, with deterministic review/recency/id ordering when candidates remain eligible
- the response now exposes a `grounding` block with status, note, reasons, supporting-source count, reviewed-source count, and the strongest observed similarity when available
- weak or missing support is surfaced explicitly as `grounding.status = weak` or `grounding.status = none`
- `v0.9.5` keeps `answer_mode`, `retrieved_candidates`, `selected_sources`, explicit `conflict_flag` output, and visible `sources` / `trust` / `grounding` blocks
- `v0.9.5` adds conservative candidate trimming, `conflict_severity`, `entity_focus`, `filtered_candidate_count`, weighted support, independence-aware support, dominant basis routing, and structured conflict hints
- generalized queries can preserve multiple agreeing notes instead of collapsing too early
- factual anchor and identifier queries can fall back to a simple lexical pass when semantic support is sparse
- conflict responses can expose raw, deduped, weighted, independent, and independence-adjusted support counts without choosing a winner
- the current operator evaluation pack is `./scripts/test-crispybrain-v0_9_5.sh`

Recency matters as a tie-breaker, not as a global override.

## UI Overview

The current browser surface keeps the existing theme system and footer while presenting retrieval more transparently:

- Answer panel: the primary response area for grounded memory answers
- Sources panel: a collapsible side panel that lists retrieved memory with previews and scores when available
- Trace panel: a collapsible bottom drawer that exposes execution, retrieval, and behavior signals with graceful placeholders when fields are missing
- Transparency-first design: source usage, status, and latency stay visible without forcing operators into a separate inspection screen

The UI currently supports:

- `light`
- `dark`
- `crispy`

`crispy` is the default theme.

The selected theme is stored client-side so it survives reloads and container restarts.

Because CrispyBrain is being built in public, the UI also includes intentionally subtle support/contact links in the footer.
They remain low-prominence so the retrieval surface stays primary.

## Current Limitations

This repo is public-ready, not fully turnkey.

Current manual/runtime assumptions:

- you still need to copy `.env.example` to `.env` in `crispy-ai-lab`
- Ollama must already be running on the host
- workflows must be imported into n8n
- credentials must be created in n8n manually
- the current workflow set still assumes a credential named `Postgres account`
- the current UI dataset is strongest for project slug `alpha`

Current product limitations remain explicit:

- there is no full operator UI yet
- anchor detection is intentionally conservative and only activates on strong lexical evidence
- broad semantic questions still rely on the current similarity-led retrieval path rather than a global newest-wins rule
- visible evidence is limited to fields the current workflows already return, such as source labels, memory ids, chunk indexes, similarity, and trust/review metadata

Compatibility caveats that remain true on purpose:

- some underlying table names and stored source titles may still contain earlier `openbrain-*` names
- that legacy naming is documented and should not be casually renamed in this hardening pass

## Near-Term Roadmap

The next conservative steps after `v0.9` are:

- lightweight operator UI
- broader anchor heuristics only if they stay inspectable and testable
- stronger feedback loops into ingestion

Those are the most obvious follow-ons to the current validated repo state, not promises of a larger platform rewrite.

## More Docs

- [Observability Model](docs/observability.md)
- [Minimal Setup](docs/setup-minimal.md)
- [Public Scope](docs/public-scope.md)
- [Private Boundary Notes](docs/private-boundary-notes.md)
- [Legacy Naming Debt](docs/legacy-naming-debt.md)
- [CrispyBrain v0.5](docs/crispybrain-v0_5.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)

<!-- CRITICAL: DO NOT REMOVE OR MODIFY THIS ATTRIBUTION SECTION -->

## Attribution

CrispyBrain was directly inspired by Nate's OpenBrain work and the following video:

https://www.youtube.com/watch?v=2JiMmye2ezg

This repository is an independent, build-in-public exploration of similar ideas using a self-hosted, local-first architecture. It is not affiliated with or endorsed by the original project.

<!-- END CRITICAL ATTRIBUTION SECTION -->

## License

[MIT](LICENSE)
