# Current State

Current version: `v1.0.0-14-g59bd5dc`

This document is the current-state anchor for the rest of the docs. Historical `v0.x` documents remain useful as release notes, but the README and this file are the docs to check first when validating the repo today.

## Source Of Truth

- requested docs stamp: `v1.0.0-14-g59bd5dc`
- `git describe --tags --always 59bd5dc`: `v1.0.0-14-g59bd5dc`
- current checkout during this refresh: `v1.0.0-20-g9a92fbc`
- only Git tag present during this refresh: `v1.0.0`

Because the branch contains later commits than `59bd5dc`, docs should avoid pretending that every later runtime detail is part of the requested version stamp. When a fact comes from the inspected checkout rather than the requested stamp, state it that way.

## Product Shape

CrispyBrain is a self-hosted local memory assistant:

```text
inbox notes or API requests
-> n8n workflow exports
-> Postgres with pgvector
-> Ollama embeddings / generation
-> answer with sources, grounding, trust, usage, and trace metadata
```

The reference Docker runtime lives in the sibling `crispy-ai-lab` repo. This repo owns the product docs, workflow exports, demo UI, helper scripts, seed data, and repo-local inbox files.

## Current Entry Points

- local browser UI: `http://localhost:8787`
- assistant webhook: `POST /webhook/assistant`
- ingest webhook: `POST /webhook/ingest`
- demo wrapper webhook: `POST /webhook/crispybrain-demo`
- JSON inbox import endpoint on the demo server: `POST /api/inbox/import`
- project API on the demo server: `GET /api/projects`, `POST /api/projects`, `DELETE /api/projects/<project-slug>`

## Runtime Facts Checked In This Refresh

- supported/documented n8n target: `2.16.1`
- inspected local n8n container: `2.17.7`
- Ollama CLI: `0.18.0`
- Postgres container: `16.13`
- pgvector extension: `0.8.2`
- Docker engine: `29.4.0`
- Docker Compose plugin: `5.1.2`
- Docker Desktop on this Mac: `4.70.0`
- documented/tested Docker Desktop target in the reference lab docs: macOS `4.69.0`
- architecture: `aarch64`

## Docs Organization

- `README.md`: short current reader path and version stamp
- `docs/current-state.md`: current facts and validation anchor
- `docs/operator-quickstart.md`: practical local setup flow
- `docs/setup-minimal.md`: minimum runtime assumptions
- `docs/demo-local.md`: browser demo and API surface
- `docs/ingest-text.md`: file-drop and JSON import behavior
- `docs/workflow-sync.md`: n8n import/export discipline
- `docs/retrieval.md`: current retrieval behavior
- `docs/trust-output.md`: trust, grounding, support, and trace fields
- `docs/crispybrain-v*.md`: historical version notes
- `docs/openbrain-history-memory-pack.md`, `docs/MIGRATION.md`, and `docs/legacy-naming-debt.md`: compatibility/history notes

## Validation Commands

```bash
git status --short
git describe --tags --always --dirty
rg -n "pre[-]v1|v0\\.9\\.5|v0\\.9\\.9|[T]ODO|[F]IXME|placeholder|crispybrain[-]assistant|crispybrain[-]ingest" README.md docs
rg -n "OPENAI[_]API[_]KEY|API[_]KEY|[T]OKEN|[S]ECRET|[P]ASSWORD|PRIVATE[_]KEY" README.md docs CHANGELOG.md
```

The stale-reference search intentionally still finds historical docs. Treat current README/setup/operator contradictions as bugs; treat versioned historical notes as context unless they claim to describe the current version.
