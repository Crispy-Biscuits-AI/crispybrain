# CrispyBrain v0.4

CrispyBrain v0.4 is the first release in the CrispyBrain fork line. It preserves the OpenBrain v0.1-v0.3 lineage in the original repository while rebranding the active assistant, simplifying workflow names, and shortening the primary webhook path.

## What v0.4 Adds

- a unified assistant workflow with internal id/name `assistant`
- session continuity backed by `openbrain_chat_turns`
- project-aware retrieval with general fallback
- a static local UI at [crispybrain-v0.4-chat.html](/Users/elric/repos/crispybrain/docs/crispybrain-v0.4-chat.html)
- import and validation scripts for `Personal -> CrispyBrain v0.4`

## Active Entrypoint

- Workflow export file: [assistant.json](/Users/elric/repos/crispybrain/workflows/assistant.json)
- Workflow id/name after import: `assistant`
- Webhook: `POST http://localhost:5678/webhook/assistant`
- n8n folder: `Personal -> CrispyBrain v0.4`

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

## Response Shape

Successful response:

```json
{
  "ok": true,
  "answer": "CrispyBrain is the independently branded evolution of OpenBrain...",
  "query": "What is CrispyBrain?",
  "session_id": "crispybrain-v0-4-session-test",
  "project_slug": "alpha",
  "top_k": 4,
  "retrieval": {
    "strategy": "project-first-fallback-general",
    "project_match_count": 2,
    "general_match_count": 1,
    "memory_count": 2,
    "strongest_similarity": 0.82,
    "similarity_threshold": 0.72,
    "empty": false
  },
  "sources": [
    {
      "id": 16,
      "title": "crispybrain-alpha-plan.txt :: chunk 01",
      "project_slug": "alpha",
      "similarity": 0.82,
      "snippet": "CrispyBrain is being built incrementally..."
    }
  ],
  "session": {
    "turn_count_before": 2,
    "history_used": true,
    "stored": true,
    "turn_count_after": 4
  }
}
```

Validation failure:

```json
{
  "ok": false,
  "error": {
    "code": "INVALID_INPUT",
    "message": "Missing or invalid query/message"
  }
}
```

## Import

Run:

```bash
./scripts/import-crispybrain-v0_4.sh
```

The import script:

1. applies [crispybrain-v0_4-upgrade.sql](/Users/elric/repos/crispybrain/sql/crispybrain-v0_4-upgrade.sql)
2. ensures the `CrispyBrain v0.4` folder exists
3. imports every valid workflow export in [workflows](/Users/elric/repos/crispybrain/workflows)
4. verifies imported workflow names do not use the `openbrain-` prefix
5. verifies the `assistant` webhook path and folder placement
6. activates the `assistant` workflow

## Test

Run:

```bash
./scripts/test-crispybrain-v0_4.sh
```

The test covers:

1. UI endpoint and theme defaults
2. localStorage migration from OpenBrain keys to CrispyBrain keys
3. plain assistant smoke request
4. project-aware retrieval
5. multi-turn session continuity
6. invalid-input handling
7. empty retrieval fallback

## Local UI

Open [crispybrain-v0.4-chat.html](/Users/elric/repos/crispybrain/docs/crispybrain-v0.4-chat.html) in a browser after importing the workflows.

The UI:

- defaults to `http://localhost:5678/webhook/assistant`
- migrates the old OpenBrain assistant endpoint automatically
- preserves custom user-entered endpoints
- stores `session_id`, `project_slug`, endpoint, and theme in CrispyBrain-specific localStorage keys
- supports `dark polarized` and `light polarized` without a page reload

## Lineage

OpenBrain v0.1-v0.3 remain preserved in `/Users/elric/repos/openbrain`. CrispyBrain begins at v0.4 in this repository as an independently branded fork that acknowledges Nate Jones and the original OpenBrain concept while diverging in branding, workflow naming, and local UX.

## Deferred

- database table renames
- authentication and access control
- streaming responses
- cleanup of older duplicate experimental workflows already present in n8n
