# CrispyBrain v0.4

This document is the technical note for the current public workflow set.

## What v0.4 Represents

`v0.4` is the first public-facing CrispyBrain release line in this repository. It establishes the current assistant webhook, workflow naming, local UI, and session continuity behavior.

## Main Entrypoint

- workflow export: [assistant.json](../workflows/assistant.json)
- imported workflow name: `assistant`
- webhook: `POST http://localhost:5678/webhook/assistant`
- optional local UI: [crispybrain-v0.4-chat.html](crispybrain-v0.4-chat.html)

Accepted request body:

```json
{
  "message": "What is CrispyBrain?",
  "project_slug": "alpha",
  "session_id": "crispybrain-v0-4-session-test",
  "top_k": 4
}
```

`query` is also accepted as an alias for `message`.

## Current Runtime Assumptions

- n8n executes the workflows
- Postgres stores `memories`, `projects`, and the session-turn table
- `sql/crispybrain-v0_4-upgrade.sql` creates the `openbrain_chat_turns` table used by the assistant workflow
- Ollama is reachable from n8n at `http://host.docker.internal:11434`

## Import And Test Helpers

For maintainers running the expected local Docker setup:

- import helper: [`scripts/import-crispybrain-v0_4.sh`](../scripts/import-crispybrain-v0_4.sh)
- test helper: [`scripts/test-crispybrain-v0_4.sh`](../scripts/test-crispybrain-v0_4.sh)

These scripts are convenience helpers, not the only supported way to run CrispyBrain.

## Local UI

The local UI:

- defaults to `http://localhost:5678/webhook/assistant`
- preserves custom endpoints
- migrates older local browser keys where needed
- supports `dark polarized` and `light polarized`

## Deferred

- renaming runtime-sensitive legacy table names
- authentication and access control
- turnkey packaging for every environment
- cleanup of older experimental workflow variants
