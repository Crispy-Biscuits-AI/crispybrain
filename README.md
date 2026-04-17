# OpenBrain

OpenBrain is a self-hosted, project-aware memory and retrieval system built with n8n, Postgres + pgvector, and Ollama.

The goal of OpenBrain is to incrementally build a durable memory layer for AI workflows while validating each small step before expanding the system.

Current OpenBrain capabilities include:

* File and manual note ingestion
* Project-aware memory storage
* Embedding generation with Ollama
* Semantic search with pgvector
* Context block construction from retrieved memories
* Answer generation from retrieved memory
* Project-scoped retrieval using `project_slug`
* A local assistant entrypoint with session continuity in v0.3
* A static local chat UI in `docs/openbrain-v0.3-chat.html`

---

# Design Principles

OpenBrain is intentionally developed with strict constraints:

* Make only atomic changes
* Preserve working behavior
* Avoid redesigning unrelated parts
* Validate every step before moving forward
* Prefer small incremental improvements over large rewrites
* Keep project memory scoped by `project_slug`
* Avoid mission creep

---

# Architecture

```text
n8n Workflow
    ↓
Normalize / Chunk Input
    ↓
Generate Embedding (Ollama)
    ↓
Store in Postgres + pgvector
    ↓
Semantic Search by Embedding
    ↓
Build Context Block
    ↓
Generate Answer From Memory
```

Current stack:

* n8n 2.16.1
* Ollama 0.18.0
* Postgres 16.13
* pgvector
* Docker Desktop 4.69.0

---

# Repository Structure

```text
.
├── README.md
├── workflows/
│   ├── openbrain-ingest.json
│   ├── openbrain-file-chunk-ingest-minimal.json
│   ├── openbrain-insert-with-chunk-metadata.json
│   ├── openbrain-insert-embedding.json
│   ├── openbrain-search-by-embedding.json
│   ├── openbrain-build-context.json
│   ├── openbrain-answer-from-memory.json
│   ├── openbrain-project-bootstrap.json
│   ├── openbrain-auto-ingest-watch.json
│   └── openbrain-validation-and-errors.json
├── sql/
│   ├── openbrain-schema.sql
│   ├── openbrain-v0_2-upgrade.sql
│   └── openbrain-indexes.sql
├── prompts/
│   └── codex-prompts/
├── docs/
└── samples/
```

---

# Workflow Overview

## v0.3 Assistant

### `openbrain-assistant`

Primary local chat entrypoint for v0.3.

Accepts:

```json
{
  "message": "What is OpenBrain?",
  "project_slug": "alpha",
  "session_id": "openbrain-v0-3-session-test",
  "top_k": 4
}
```

Responsibilities:

* validate chat inputs and return machine-readable JSON errors
* load recent session turns from `openbrain_chat_turns`
* run project-first retrieval with general-memory fallback
* generate a local Ollama answer
* store both user and assistant turns for later continuity
* return source snippets and retrieval metadata for debugging and UI display

## Ingest Workflows

### `openbrain-ingest`

Primary entry point for ingestion.

Accepts:

```json
{
  "filepath": "...",
  "filename": "...",
  "content": "...",
  "project_slug": "alpha"
}
```

Responsibilities:

* Normalize input
* Chunk large content
* Generate embeddings
* Store memories in Postgres

### `openbrain-auto-ingest-watch`

Automatically watches the mounted inbox folder and forwards new files into `openbrain-ingest`.

Expected inbox structure:

```text
/home/node/.n8n-files/openbrain/inbox/
/home/node/.n8n-files/openbrain/inbox/alpha/
/home/node/.n8n-files/openbrain/inbox/project-x/
```

Project-aware routing:

```text
inbox/alpha/file.txt      -> project_slug = alpha
inbox/project-x/file.txt  -> project_slug = project-x
inbox/file.txt            -> no project_slug
```

---

## Retrieval Workflows

### `openbrain-search-by-embedding`

Accepts a query, generates an embedding, and returns the most relevant memories.

### `openbrain-build-context`

Formats retrieved memories into a clean context block.

### `openbrain-answer-from-memory`

Combines:

* semantic retrieval
* context construction
* answer generation

Example request:

```bash
curl -X POST "http://localhost:5678/webhook/openbrain-answer-from-memory" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is the current OpenBrain architecture?",
    "project_slug": "alpha"
  }'
```

---

# Database

OpenBrain stores memory records in Postgres using pgvector.

Core table:

```text
memories
```

Important columns:

| Column        | Purpose                |
| ------------- | ---------------------- |
| id            | Memory ID              |
| title         | Human-readable title   |
| content       | Original memory text   |
| embedding     | Vector embedding       |
| category      | Memory type            |
| source        | Origin of the memory   |
| metadata_json | Structured metadata    |
| project_slug  | Optional project scope |
| created_at    | Timestamp              |

Example metadata:

```json
{
  "filename": "openbrain-alpha-architecture.txt",
  "chunk_index": 1,
  "total_chunks": 1,
  "project_slug": "alpha",
  "ingested_at": "2026-04-16T08:39:09.395Z"
}
```

---

# Setup

## 1. Start the stack

```bash
docker compose up -d
```

## 2. Ensure the inbox folder is mounted into the n8n container

Example Docker Compose volume:

```yaml
volumes:
  - /Users/elric/repos/ai-lab/openbrain/inbox:/home/node/.n8n-files/openbrain/inbox
```

## 3. Import the v0.3 assistant

Run:

```bash
./scripts/import-openbrain-v0_3.sh
```

This applies the additive v0.3 SQL, imports `workflows/openbrain-assistant.json`, verifies the workflow lands in `Personal -> OpenBrain v0.3`, and activates the assistant webhook.

---

# Example Usage

Assistant chat:

```bash
curl -X POST "http://localhost:5678/webhook/openbrain-assistant" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "How am I planning to build OpenBrain?",
    "project_slug": "alpha",
    "session_id": "readme-example-session"
  }'
```

Static local UI:

* [docs/openbrain-v0.3-chat.html](/Users/elric/repos/openbrain/docs/openbrain-v0.3-chat.html)

Manual ingest:

```bash
curl -X POST "http://localhost:5678/webhook/openbrain-ingest" \
  -H "Content-Type: application/json" \
  -d '{
    "filename": "architecture.txt",
    "content": "OpenBrain uses n8n, pgvector, and Ollama.",
    "project_slug": "alpha"
  }'
```

Search:

```bash
curl -X POST "http://localhost:5678/webhook/openbrain-search-by-embedding" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is OpenBrain built with?",
    "project_slug": "alpha"
  }'
```

---

# Current Maturity Snapshot

| Area                       | Status |
| -------------------------- | ------ |
| Infrastructure             | 90%    |
| Memory ingestion           | 100%   |
| Embedding pipeline         | 100%   |
| Semantic retrieval         | 90%    |
| Answer generation          | 80%    |
| Unified assistant behavior | 40%    |
| Automation and scaling     | 10%    |

---

# Planned Next Steps

1. Improve `openbrain-build-context`
2. Add stronger project memory awareness
3. Finalize automatic file watching
4. Improve validation and error handling
5. Add automation and scaling
6. Eventually support multiple projects and project-specific memory boundaries

---

# v0.3 Validation

Run:

```bash
./scripts/test-openbrain-v0_3.sh
```

The test covers:

1. plain chat request
2. request with `project_slug`
3. multi-turn session continuity
4. invalid input
5. empty retrieval

Focused v0.3 documentation:

* [docs/openbrain-v0.3.md](/Users/elric/repos/openbrain/docs/openbrain-v0.3.md)

---

# Development Workflow

Recommended git discipline:

* One atomic change per commit
* One workflow change at a time
* Commit only files intentionally changed
* Avoid mixing generated and manual changes

Example commit message:

```text
feat(openbrain): add project-aware auto-ingest watcher
```

---

# License

Private internal project for Crispy Biscuits AI.

OpenBrain is under active development and intentionally optimized for iterative, validated experimentation rather than broad public release.
