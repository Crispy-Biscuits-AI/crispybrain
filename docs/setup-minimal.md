# Minimal Setup

## Goal

A minimum working CrispyBrain setup means:

- the `assistant` webhook accepts a request
- the assistant retrieves from `memories`
- Ollama generates the response
- the conversation turn is stored in the session-turn table

## Required Runtime

### n8n

The product logic is stored as exported n8n workflows in `workflows/`.

### Postgres With pgvector

The workflows depend on Postgres for:

- stored memory rows in `memories`
- project metadata in `projects`
- assistant session history in `openbrain_chat_turns`

This repo includes `sql/crispybrain-v0_4-upgrade.sql` for the session-turn table only. It does not fully provision the `memories` or `projects` schema from scratch.

### Ollama

The checked-in workflows call Ollama directly at:

```text
http://host.docker.internal:11434
```

Required models:

- `llama3`
- `nomic-embed-text`

## Required n8n Credential

Create a Postgres credential named `Postgres account`.

Several workflow exports currently embed that credential name directly, so changing it requires editing and re-exporting the workflows.

## Import Notes

- Import order is not strict, but importing the stable workflow set together is the least confusing path.
- The `assistant` workflow is the main entrypoint.
- Older `insert-embedding-fixed*.json` files are historical workflow variants, not the recommended starting point.

## Host-Side Assumptions

- n8n can reach host Ollama through `host.docker.internal`
- Postgres accepts connections from n8n
- the `memories` table already contains relevant memory rows if you expect meaningful answers immediately

## Optional Local UI

`docs/crispybrain-v0.4-chat.html` is a simple local UI for testing the assistant webhook. It is optional and not required for the core runtime.

## If You Need A Reference Environment

This repo stands on its own as the public product repo. If you want a broader local reference environment, `crispy-ai-lab` can be used separately, but it is optional.
