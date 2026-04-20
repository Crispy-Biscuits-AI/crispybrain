<p align="center">
  <img src="assets/crispybrain-biscuit.png" alt="CrispyBrain tea biscuit" width="220">
</p>

<h1 align="center">CrispyBrain</h1>

<p align="center">
  CrispyBrain is a local-first AI memory system focused on knowledge quality, trust visibility, and operator control — with a real demo UI, n8n workflow pipeline, and self-hosted lab runtime.
</p>

`crispybrain` is the public product/demo repo for CrispyBrain: an open-source, self-hosted memory, retrieval, and agent lab built around real n8n workflow exports and a real local demo path.

It is the place to understand the current demo surface, the workflow shape, the public product direction, and the local runtime path that ends at `http://localhost:8787` when run through the sibling `crispy-ai-lab` repo.

## Start Here

- [Local demo](docs/demo-local.md)
- [Ingest data](docs/ingest-text.md)
- [Operator tools](docs/operator-quickstart.md)

## Current Status

CrispyBrain is still an early, real, build-in-public system.

- local-first and self-hosted
- good for showing the current product slice honestly
- not production-ready
- not a turnkey hosted platform
- `v0.5` added structured tracing, boundary validation, and ingest replay detection
- `v0.6` is the quality and control release
- `v0.7.1` is the current stability patch for anchor-aware deterministic retrieval
- `v0.8` is the current trust and evaluation release

The validated `v0.8` state adds:

- trust visibility and source-quality indicators in responses
- review-state controls and project health visibility
- upgraded memory inspection and operator tooling
- suspect review/export workflows and metrics snapshots
- a validated multi-cycle runtime harness
- conservative anchor-aware note lookup with deterministic reviewed/recency tie-breaking
- explicit grounding notes and weak-grounding states in assistant and demo responses
- a repeatable 8-case evaluation pack for operator inspection

## Why CrispyBrain Exists

CrispyBrain exists to make a local memory-backed assistant path visible and inspectable instead of magical.

The repo is intentionally honest about the current slice:

- a real demo UI
- a real n8n orchestration path
- grounded retrieval instead of mocked answers
- operator-facing inspection tools for memory quality

## What It Can Do Today

Today’s checked-in repo surface can:

- run a real demo flow through `crispybrain-demo` and `assistant`
- retrieve memory-backed answers instead of static demo text
- answer exact note-name and strong anchor-style note lookups deterministically
- expose trust and source metadata in responses
- expose grounding status, supporting-source counts, and visible evidence fields in the demo path
- let operators inspect memory quality by project
- export suspect rows and snapshot health over time
- update review state for stored memory rows through the memory inspector
- run a repo-tracked 8-case retrieval evaluation pack with compact diagnostics

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

## Repository Structure

- `demo/`: the current demo UI and local proxy server
- `workflows/`: exported n8n workflow JSON, including `assistant` and `crispybrain-demo`
- `sql/`: checked-in SQL needed by the current assistant path
- `scripts/`: maintainer and local helper scripts
- `docs/`: setup, demo, scope, and technical notes
- `assets/`: public artwork used by the demo and docs

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

4. In n8n, create a Postgres credential named `Postgres account`, then activate `assistant` and `crispybrain-demo`.

5. Open the demo UI at `http://localhost:8787`.

6. Use:

- project slug: `alpha`
- question: `How am I planning to build CrispyBrain?`

Success currently looks like:

- the page loads on `localhost:8787`
- the theme selector is available
- the response includes an answer, a grounding note, and source rows
- the `debug` block shows the request passed through the demo workflow path

## Demo, Workflow, Ingestion, and Operator Entry Points

Use these docs as the next stop depending on what you want to do:

- [Local Demo](docs/demo-local.md): run the `8787` demo path and verify the UI/workflow flow
- [Operator Quickstart](docs/operator-quickstart.md): get the fastest realistic operator setup
- [Ingesting Text](docs/ingest-text.md): drop plain text into the current ingest path safely
- [Workflow Sync](docs/workflow-sync.md): keep checked-in workflow exports aligned with n8n
- [CrispyBrain v0.8](docs/crispybrain-v0_8.md): trust and evaluation release notes, grounding behavior, and the 8-case harness
- [CrispyBrain v0.7](docs/crispybrain-v0_7.md): anchor-aware deterministic retrieval, harness coverage, and validation notes
- [CrispyBrain v0.6](docs/crispybrain-v0_6.md): release summary, runtime validation notes, and known limitations

## Memory Quality and Trust

`v0.6` introduced the first real quality-and-control layer in the public repo.
`v0.7.1` keeps that layer in place and makes retrieval policy explicit.
`v0.8` adds clearer operator-visible grounding and a repeatable evaluation pack.

That includes:

- project memory health visibility
- source quality indicators in assistant and demo responses
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
- the current operator evaluation pack is `./scripts/test-crispybrain-v0_8.sh`

Recency matters as a tie-breaker, not as a global override.

## Demo Surface and Themes

The demo UI currently supports:

- `light`
- `dark`
- `crispy`

`crispy` is the default theme.

The selected theme is stored client-side so it survives reloads and container restarts.

Because CrispyBrain is being built in public, the demo also includes intentionally subtle support/contact links in the footer.
They are optional and kept low-prominence so the UI still reads as a demo first.

## Current Limitations

This repo is public-ready, not fully turnkey.

Current manual/runtime assumptions:

- you still need to copy `.env.example` to `.env` in `crispy-ai-lab`
- Ollama must already be running on the host
- workflows must be imported into n8n
- credentials must be created in n8n manually
- the current workflow set still assumes a credential named `Postgres account`
- the current demo dataset is strongest for project slug `alpha`

Current product limitations remain explicit:

- there is no full operator UI yet
- anchor detection is intentionally conservative and only activates on strong lexical evidence
- broad semantic questions still rely on the current similarity-led retrieval path rather than a global newest-wins rule
- visible evidence is limited to fields the current workflows already return, such as source labels, memory ids, chunk indexes, similarity, and trust/review metadata

Compatibility caveats that remain true on purpose:

- some underlying table names and stored source titles may still contain earlier `openbrain-*` names
- that legacy naming is documented and should not be casually renamed in this hardening pass

## Near-Term Roadmap

The next conservative steps after `v0.8` are:

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
