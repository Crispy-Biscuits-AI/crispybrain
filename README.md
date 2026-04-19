<p align="center">
  <img src="assets/crispybrain-biscuit.png" alt="CrispyBrain tea biscuit" width="220">
</p>

<h1 align="center">CrispyBrain</h1>

<p align="center">
  A self-hosted project memory assistant built with n8n, Postgres, and Ollama.
</p>

CrispyBrain is a practical local-first assistant for teams and individuals who want to ingest notes, keep project memory searchable, and answer questions from that memory through a simple webhook-driven workflow stack.

This repository is the public product repo for CrispyBrain. It includes the workflow exports, SQL, scripts, and docs needed to understand and run the current system. It does not try to be a full private operations repo, a CMS repo, or a general AI lab.

## Who It Is For

- operators who already run or can provision `n8n`, Postgres, and Ollama
- developers who want a concrete reference implementation for local memory retrieval
- consultants or technical teams evaluating a small self-hosted AI memory stack

## What Problem It Solves

CrispyBrain gives you a workflow-based assistant that:

- ingests project notes into Postgres
- embeds and retrieves memory with Ollama
- answers questions from stored context
- keeps short session history for conversational continuity

## What Is In This Repo

- `workflows/`: exported n8n workflow JSON files
- `sql/`: the checked-in SQL migration used by the current workflow set
- `scripts/`: import, test, and local helper scripts for maintainers
- `docs/`: onboarding, scope, setup, release, and technical notes
- `assets/`: public repo artwork

## Minimum Runtime

The smallest practical CrispyBrain setup today is:

1. `n8n`
2. Postgres with `pgvector`
3. Ollama reachable from n8n at `http://host.docker.internal:11434`

The checked-in workflows expect:

- a Postgres credential in n8n named `Postgres account`
- a `memories` table and a `projects` table already available in Postgres
- the session-turn table created by `sql/crispybrain-v0_4-upgrade.sql`
- Ollama models `llama3` and `nomic-embed-text`

## Quickstart

1. Read [Operator Quickstart](docs/operator-quickstart.md).
2. Follow [Minimal Setup](docs/setup-minimal.md).
3. Import or sync the workflows from [workflows/](workflows/).
4. Review [Workflow Sync](docs/workflow-sync.md) before editing workflows in n8n.
5. Check [Public Scope](docs/public-scope.md) for what this repo does and does not include.

The main public entrypoint is the `assistant` workflow at:

```text
POST http://localhost:5678/webhook/assistant
```

Example request:

```bash
curl -X POST "http://localhost:5678/webhook/assistant" \
  -H "Content-Type: application/json" \
  -d '{"message":"What is CrispyBrain?"}'
```

## Current Core Workflows

The current public product path is centered on stable workflow exports such as:

- `assistant.json`
- `ingest.json`
- `search-by-embedding.json`
- `build-context.json`
- `project-memory.json`
- `project-bootstrap.json`
- `validation-and-errors.json`

Some additional workflow JSON files in `workflows/` are older experiments or intermediate fixes. They are kept for reference, not as the primary onboarding path.

## What Is Intentionally Out Of Scope

This repo does not currently include:

- CMS implementation material
- client-specific integrations
- managed hosting or SaaS packaging
- production auth/access control
- a fully self-contained Docker environment

## Relationship To `crispy-ai-lab`

`crispy-ai-lab` is a separate optional reference environment where CrispyBrain can be developed, tested, or run alongside broader lab tooling. It is not required to understand this repo, and it is not the public product identity for CrispyBrain.

## Docs

- [Operator Quickstart](docs/operator-quickstart.md)
- [Minimal Setup](docs/setup-minimal.md)
- [Workflow Sync](docs/workflow-sync.md)
- [Public Scope](docs/public-scope.md)
- [Private Boundary Notes](docs/private-boundary-notes.md)
- [Legacy Naming Debt](docs/legacy-naming-debt.md)
- [v0.4 Technical Note](docs/crispybrain-v0.4.md)
- [Migration Notes](docs/MIGRATION.md)
- [History](docs/HISTORY.md)

## Status

This repo is ready for an early public release as a technical, self-hosted CrispyBrain reference implementation. The documentation is intentionally explicit about current limitations so the public story stays truthful.
