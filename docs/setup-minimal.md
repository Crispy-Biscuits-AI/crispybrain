# Minimal Setup

Current version: `v1.0.0-14-g59bd5dc`

This is the smallest runtime shape that matches the checked-in workflow exports. It is not a one-command installer.

## Minimum Runtime

- n8n to run exported workflows from `workflows/`
- Postgres with pgvector for memory, project, embedding, and session data
- Ollama reachable from n8n at `http://host.docker.internal:11434`
- an n8n Postgres credential named `Postgres account`

Required Ollama models:

- `llama3`
- `nomic-embed-text`

## Database Assumptions

The current workflows use:

- `memories`
- `projects`
- `openbrain_chat_turns`

This repo includes `sql/crispybrain-v0_4-upgrade.sql` for the session-turn table. It does not fully bootstrap every table needed by all workflow paths from scratch.

## Workflow Assumptions

Recommended current entrypoints:

- `assistant`
- `ingest`
- `crispybrain-demo`
- optional `auto-ingest-watch`

Older `insert-embedding-fixed*.json` and other variant exports are retained as historical or helper workflow snapshots. They are not the starting point for a minimal operator setup.

## Reference Environment

The maintainer reference runtime is the sibling `crispy-ai-lab` repo. Use it when you want the documented Docker path:

```bash
cd /Users/elric/repos/crispy-ai-lab
../crispybrain/scripts/set-version-env.sh up -d postgres n8n crispybrain-demo-ui
```

Supported/documented target facts checked during this refresh:

- n8n target in docs/minimal Compose: `2.16.1`
- Ollama CLI: `0.18.0`
- Postgres container: `16.13`
- pgvector extension: `0.8.2`
- architecture: `aarch64`

The inspected local main Compose n8n container was `2.17.7`, so verify runtime behavior after any n8n upgrade.

## Optional Local UI

The current browser demo is served at:

```text
http://localhost:8787
```

The older `docs/crispybrain-v0.4-chat.html` file remains in the repo as historical/fallback documentation. Prefer the `demo/` service for the current local UI.
