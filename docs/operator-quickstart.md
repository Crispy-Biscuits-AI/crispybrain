# Operator Quickstart

Use this if you want the fastest realistic path to a working CrispyBrain instance.

## 1. Prepare The Runtime

You need:

- `n8n`
- Postgres with `pgvector`
- Ollama running on the host and reachable from n8n at `http://host.docker.internal:11434`

Required Ollama models:

- `llama3`
- `nomic-embed-text`

## 2. Prepare The Database

This repo includes `sql/crispybrain-v0_4-upgrade.sql`, which creates the session-turn table used by the assistant workflow.

The workflow set also expects these existing tables to already be present:

- `memories`
- `projects`

## 3. Create The n8n Credential

Create a Postgres credential in n8n named:

```text
Postgres account
```

The checked-in workflow exports expect that exact credential name.

## 4. Import The Workflows

Import the workflow JSON files in `workflows/` into n8n.

Start with the stable public path:

- `assistant.json`
- `ingest.json`
- `search-by-embedding.json`
- `build-context.json`
- `project-memory.json`
- `project-bootstrap.json`
- `validation-and-errors.json`

## 5. Activate The Assistant

Activate the `assistant` workflow and verify that the webhook is available at:

```text
http://localhost:5678/webhook/assistant
```

## 6. Smoke Test

```bash
curl -X POST "http://localhost:5678/webhook/assistant" \
  -H "Content-Type: application/json" \
  -d '{"message":"What is CrispyBrain?"}'
```

## 7. Optional Helpers

- `scripts/import-crispybrain-v0_4.sh` can automate import in a compatible local Docker setup
- `scripts/test-crispybrain-v0_4.sh` can run a local validation pass in that same style of setup

Those scripts are maintainer conveniences, not the only supported onboarding path.
