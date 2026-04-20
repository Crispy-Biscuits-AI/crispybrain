# Operator Quickstart

Use this if you want the fastest realistic path to a working CrispyBrain instance with the current trust-and-evaluation release.

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

## 4. Import The Repo-Owned Workflows

The minimum public path for local operator validation is:

- `workflows/assistant.json`
- `workflows/crispybrain-demo.json`
- `workflows/ingest.json`

Optional if your local runtime really uses a watch handoff:

- `workflows/auto-ingest-watch.json`

Recommended import path:

```bash
cd ../crispy-ai-lab
WORKFLOW_DIR=../crispybrain/workflows \
CONFIRM_IMPORT=I_UNDERSTAND \
scripts/workflows/import-exported-into-docker.sh
```

## 5. Create The Repo-Owned Inbox Folder

The canonical CrispyBrain ingest path is:

```text
/Users/elric/repos/crispybrain/inbox/<project-slug>/
```

For the default project:

```bash
mkdir -p /Users/elric/repos/crispybrain/inbox/alpha
```

Put plain `.txt` notes in that folder if your local watch path is wired to the repo-owned inbox.

## 6. Activate The Webhook Workflows

Activate:

- `assistant`
- `ingest`
- `crispybrain-demo`

Optional:

- `auto-ingest-watch` only if your external watch/runtime is wired to call it

Recommended n8n organization:

- place the canonical workflows under `Personal -> CrispyBrain`

Folder placement is organizational only. The live runtime is determined by:

- the workflow `active` toggle
- the webhook path or trigger the caller actually uses

Verify the webhooks are available at:

```text
http://localhost:5678/webhook/assistant
http://localhost:5678/webhook/ingest
http://localhost:5678/webhook/crispybrain-demo
```

## 7. Smoke Test The Assistant Path

```bash
curl -sS \
  -H "Content-Type: application/json" \
  -d '{"message":"How am I planning to build CrispyBrain?","project_slug":"alpha"}' \
  http://localhost:5678/webhook/assistant | jq '{ok,grounding,retrieval,top_source:(.sources[0] // null),trace}'
```

Inspect:

- `grounding.status`
- `grounding.note`
- `grounding.supporting_source_count`
- `retrieval.memory_count`
- the first source row if one exists

## 8. Run The `v0.8` Evaluation Pack

Use the repo-tracked harness:

```bash
./scripts/test-crispybrain-v0_8.sh
```

The harness runs exactly 8 evaluation cases covering:

- semantic match
- exact phrase match
- ambiguity / weak query
- no-strong-match query
- near-neighbor / distractor query
- multi-memory style query
- grounding visibility check
- regression-style query

The terminal output prints, for each case:

- case id
- query
- expected behavior
- pass/fail
- compact diagnostic JSON

## 9. What `v0.8` Adds For Operators

The current workflows now surface:

- a top-level `grounding` block in assistant and demo responses
- explicit `weak` and `none` grounding states when support is limited
- source evidence fields already available in the workflow output, including memory ids, trust bands, review state, similarity, and chunk indexes when present

`v0.8` does not invent confidence scores or hidden quality labels beyond the observable fields already present in the repo-owned path.

This quickstart does not change protected runtime files such as Docker Compose, so automatic watch-based ingest still depends on your external runtime being wired to the repo-owned inbox path above.
