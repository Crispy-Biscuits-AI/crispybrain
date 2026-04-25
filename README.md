<p align="center">
  <img src="assets/crispybrain-biscuit.png" alt="CrispyBrain tea biscuit" width="220">
</p>

<h1 align="center">CrispyBrain</h1>

<p align="center">
  Local-first project memory with inspectable retrieval, trust, and trace output.
</p>

Current version: `v1.0.0-14-g59bd5dc`

`crispybrain` is the public product repo for CrispyBrain. It contains the demo UI, exported n8n workflows, SQL migration material, seed/evaluation data, helper scripts, and documentation for a self-hosted memory assistant built on n8n, Postgres with pgvector, and Ollama.

The current product path is intentionally small and inspectable: notes are ingested into project memory, the assistant retrieves relevant stored chunks, and answers include evidence, grounding, trace, and token-usage metadata when the upstream model reports it.

## Latest Capabilities

<!-- AUTO-GENERATED:BEGIN Latest Capabilities -->
- Evidence-aware retrieval with semantic candidates, lexical fallback, and conservative candidate trimming
- Explicit conflict handling instead of forced answer collapse
- Source quality, source independence, duplicate-aware support, and weighted support metadata where returned by the workflow path
- Structured `usage`, `grounding`, `trust`, `retrieval`, and `trace` output in the assistant/demo response surface
- Provider-reported token usage when Ollama returns counts; explicit unavailable states when counts are absent
- Browser demo on `http://localhost:8787` with project selection, project create/delete, sources, trace, and Markdown answer export controls
- Repo-backed inbox project folders under `inbox/<project-slug>/`
- Local inbox import endpoint for safe JSON file drops, including the `Curated Articles` project key used by Agentic AI Curator exports
- Version injection for the Docker-served demo UI through `scripts/set-version-env.sh`
<!-- AUTO-GENERATED:END Latest Capabilities -->

## What It Is

CrispyBrain is a technical local-first memory system, not a hosted SaaS and not a generic chatbot. Its useful surface is the concrete workflow path:

```text
browser or API caller
-> localhost:8787 or /webhook/assistant
-> n8n workflow exports
-> Postgres memory rows with pgvector embeddings
-> Ollama generation and embedding calls
-> answer plus sources, grounding, trust, usage, and trace metadata
```

The sibling `crispy-ai-lab` repo is the reference Docker runtime used by the maintainer. This repo is the product/documentation/workflow source. The docs describe that relationship where setup steps cross the repo boundary.

## Current Architecture

- `demo/`: browser UI and local proxy server for the `8787` demo path
- `workflows/`: exported n8n workflow JSON snapshots
- `sql/`: SQL migration material owned by this repo
- `scripts/`: maintainer/operator helpers and validation harnesses
- `seed-data/`: evaluation seeds and metrics snapshots
- `inbox/`: repo-local file-drop memory projects
- `docs/`: operator, setup, sync, trust, retrieval, release, and historical notes
- `assets/`: artwork used by docs and UI

Canonical workflow entrypoints documented for the current product path:

- `assistant`
- `ingest`
- `crispybrain-demo`
- optional `auto-ingest-watch`

Canonical public webhooks:

- `POST /webhook/assistant`
- `POST /webhook/ingest`
- `POST /webhook/crispybrain-demo`

Legacy `crispybrain-*` and `openbrain-*` names still appear in historical docs, table names, and migration notes. They are documented compatibility debt, not a reason to rename runtime objects casually.

## Verified Runtime Facts

These facts were checked during this docs refresh without changing runtime state:

- requested docs version stamp: `v1.0.0-14-g59bd5dc`
- current checkout at refresh time: `v1.0.0-20-g9a92fbc`
- `git describe --tags --always 59bd5dc`: `v1.0.0-14-g59bd5dc`
- n8n supported/documented target: `2.16.1`
- currently inspected local n8n container: `2.17.7`
- Ollama CLI: `0.18.0`
- Postgres container: `16.13`
- pgvector extension: `0.8.2`
- Docker engine: `29.4.0`
- Docker Compose plugin: `5.1.2`
- Docker Desktop on this Mac: `4.70.0`
- documented/tested Docker Desktop target in the reference lab docs: macOS `4.69.0`
- architecture: `aarch64`

The version mismatch is intentional documentation honesty: the requested public docs stamp points at commit `59bd5dc`, while this branch contains later commits. See [CHANGELOG.md](CHANGELOG.md) for the source-of-truth notes.

## Setup Entry Points

Start with the docs that match your task:

- [Current State](docs/current-state.md): current architecture, supported facts, and validation commands
- [Operator Quickstart](docs/operator-quickstart.md): fastest realistic local path
- [Minimal Setup](docs/setup-minimal.md): smallest runtime shape and assumptions
- [Local Demo](docs/demo-local.md): browser demo and `8787` API behavior
- [Ingesting Text](docs/ingest-text.md): file-drop and JSON import paths
- [Workflow Sync](docs/workflow-sync.md): keeping exported workflows aligned with n8n
- [Retrieval](docs/retrieval.md): retrieval behavior and limitations
- [Trust Output](docs/trust-output.md): trust, support, conflict, and trace fields

Historical release notes remain under `docs/crispybrain-v*.md`. They describe when behavior was introduced and should not be read as the current version stamp.

## Quick Local Path

The most complete documented path uses this repo beside `crispy-ai-lab`:

```bash
cd /Users/elric/repos/crispy-ai-lab
../crispybrain/scripts/set-version-env.sh up -d postgres n8n crispybrain-demo-ui

WORKFLOW_DIR=../crispybrain/workflows \
CONFIRM_IMPORT=I_UNDERSTAND \
scripts/workflows/import-exported-into-docker.sh
```

Then create the n8n Postgres credential named `Postgres account`, activate `assistant`, `ingest`, and `crispybrain-demo`, and open:

```text
http://localhost:8787
```

For direct API smoke testing:

```bash
curl -sS \
  -H "Content-Type: application/json" \
  -d '{"message":"How am I planning to build CrispyBrain?","project_slug":"alpha"}' \
  http://localhost:5678/webhook/assistant | jq '{ok,answer,usage,grounding,trace}'
```

## Inbox And Projects

The canonical repo-owned inbox shape is:

```text
/Users/elric/repos/crispybrain/inbox/<project-slug>/
```

The demo server can also accept safe local JSON file imports:

```bash
curl -sS -X POST http://localhost:8787/api/inbox/import \
  -H 'Content-Type: application/json' \
  --data '{"project_slug":"Curated Articles","files":[{"filename":"example.md","content":"Exported note text\n","source":"agentic-ai-curator"}]}'
```

Accepted files are written under the chosen inbox project. Duplicate filenames and unsafe paths are rejected instead of overwriting existing files.

## Documentation Freshness

Use these checks before trusting or publishing docs:

```bash
git status --short
git describe --tags --always --dirty
rg -n "pre[-]v1|v0\\.9\\.5|v0\\.9\\.9|[T]ODO|[F]IXME|placeholder|crispybrain[-]assistant|crispybrain[-]ingest" README.md docs
rg -n "OPENAI[_]API[_]KEY|API[_]KEY|[T]OKEN|[S]ECRET|[P]ASSWORD|PRIVATE[_]KEY" README.md docs CHANGELOG.md
```

For runtime drift, compare the docs against:

- `workflows/*.json`
- `demo/server.py`
- `scripts/set-version-env.sh`
- the sibling `crispy-ai-lab` Compose files if you are using that reference runtime

## Current Limitations

- The repo is not a one-command turnkey installer.
- n8n credentials are still configured manually after workflow import.
- The exported workflows expect a credential named `Postgres account`.
- Ollama must already be running and reachable from n8n at `http://host.docker.internal:11434`.
- Some current behavior depends on the reference `crispy-ai-lab` runtime wiring.
- Historical `openbrain_*` names remain in compatibility-sensitive places.
- Token counts are provider-reported only; CrispyBrain does not estimate missing usage.

## More Docs

- [CHANGELOG.md](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)
- [Legacy Naming Debt](docs/legacy-naming-debt.md)
- [History](docs/HISTORY.md)
- [Migration](docs/MIGRATION.md)
- [Public Scope](docs/public-scope.md)

<!-- CRITICAL: DO NOT REMOVE OR MODIFY THIS ATTRIBUTION SECTION -->

## Attribution

CrispyBrain was directly inspired by Nate's OpenBrain work and the following video:

https://www.youtube.com/watch?v=2JiMmye2ezg

This repository is an independent, build-in-public exploration of similar ideas using a self-hosted, local-first architecture. It is not affiliated with or endorsed by the original project.

<!-- END CRITICAL ATTRIBUTION SECTION -->

## License

[MIT](LICENSE)
