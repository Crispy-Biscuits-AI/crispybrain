# OpenBrain v0.3

OpenBrain v0.3 adds a single local assistant entrypoint with:

* session continuity backed by `openbrain_chat_turns`
* project-aware retrieval with general-memory fallback
* a static local chat UI at [openbrain-v0.3-chat.html](/Users/elric/repos/openbrain/docs/openbrain-v0.3-chat.html)
* stronger machine-readable validation and error responses

## Entrypoint

Workflow:

* `workflows/openbrain-assistant.json`

Webhook:

* `POST /webhook/openbrain-assistant`

Accepted request body:

```json
{
  "message": "What is OpenBrain?",
  "project_slug": "alpha",
  "session_id": "openbrain-v0-3-session-test",
  "top_k": 4
}
```

`query` is also accepted as an alias for `message`.

## Response Shape

Successful response:

```json
{
  "ok": true,
  "answer": "OpenBrain is ...",
  "query": "What is OpenBrain?",
  "session_id": "openbrain-v0-3-session-test",
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
      "title": "openbrain-alpha-plan.txt :: chunk 01",
      "project_slug": "alpha",
      "similarity": 0.82,
      "snippet": "OpenBrain is being built incrementally..."
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

## Import and Activation

Use:

```bash
./scripts/import-openbrain-v0_3.sh
```

The script:

1. applies `sql/openbrain-v0_3-upgrade.sql`
2. imports `workflows/openbrain-assistant.json`
3. verifies the workflow is in `Personal -> OpenBrain v0.3`
4. activates the assistant entrypoint

## Test Command

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

## Local UI

Open [openbrain-v0.3-chat.html](/Users/elric/repos/openbrain/docs/openbrain-v0.3-chat.html) in a browser after running the import script.

The page:

* talks to `http://localhost:5678/webhook/openbrain-assistant`
* preserves `session_id` in browser storage
* accepts an optional `project_slug`
* shows source and retrieval metadata inline

## Deferred

These remain out of scope for v0.3:

* richer workflow-to-workflow orchestration across the older helper workflows
* multi-project authorization boundaries
* streaming responses
* automated UI packaging beyond a plain static HTML page
