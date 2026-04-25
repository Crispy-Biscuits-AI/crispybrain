# Operator Quickstart

Current version: `v1.0.0-14-g59bd5dc`

Use this for the fastest realistic path to a local CrispyBrain instance. It assumes the sibling `crispy-ai-lab` reference runtime is available.

## 1. Runtime Requirements

- n8n workflow runtime
- Postgres with pgvector
- Ollama on the host at `http://host.docker.internal:11434`
- repo checkout at `/Users/elric/repos/crispybrain`
- reference runtime checkout at `/Users/elric/repos/crispy-ai-lab`

Checked facts during this docs refresh:

- documented/supported n8n target: `2.16.1`
- inspected local n8n container: `2.17.7`
- Ollama CLI: `0.18.0`
- Postgres container: `16.13`
- pgvector extension: `0.8.2`
- architecture: `aarch64`

Required Ollama models:

- `llama3`
- `nomic-embed-text`

## 2. Start The Reference Runtime

```bash
cd /Users/elric/repos/crispy-ai-lab
../crispybrain/scripts/set-version-env.sh up -d postgres n8n crispybrain-demo-ui
```

Use the wrapper so `CRISPYBRAIN_APP_VERSION` is injected into the demo UI and the repo inbox mount is available to the UI service.

## 3. Import Workflows

```bash
cd /Users/elric/repos/crispy-ai-lab
WORKFLOW_DIR=../crispybrain/workflows \
CONFIRM_IMPORT=I_UNDERSTAND \
scripts/workflows/import-exported-into-docker.sh
```

Minimum current workflow path:

- `assistant`
- `ingest`
- `crispybrain-demo`

Optional if the file-drop watcher is part of your local run:

- `auto-ingest-watch`

## 4. Configure n8n

Create a Postgres credential named exactly:

```text
Postgres account
```

The checked-in workflow exports expect that credential name.

Activate:

- `assistant`
- `ingest`
- `crispybrain-demo`

Activate `auto-ingest-watch` only when the n8n container can see:

```text
/home/node/.n8n-files/crispybrain/inbox
```

The reference lab maps that path from:

```text
/Users/elric/repos/crispybrain/inbox
```

## 5. Create An Inbox Project

```bash
mkdir -p /Users/elric/repos/crispybrain/inbox/alpha
```

Plain text file drops should use:

```text
/Users/elric/repos/crispybrain/inbox/<project-slug>/
```

Agentic AI Curator article exports use the project key `Curated Articles`.

## 6. Open The Demo

```text
http://localhost:8787
```

Expected demo surface:

- project selector backed by immediate folders under `inbox/`
- project create/delete controls
- query form
- answer panel
- sources panel
- trace and usage panel
- Markdown export controls for the rendered answer state

## 7. Direct Assistant Smoke Test

```bash
curl -sS \
  -H "Content-Type: application/json" \
  -d '{"message":"How am I planning to build CrispyBrain?","project_slug":"alpha"}' \
  http://localhost:5678/webhook/assistant | jq '{ok,answer,usage,grounding,retrieval,trace}'
```

Inspect:

- `ok`
- `usage.available`
- token fields when usage is available
- `usage.reason` when usage is unavailable
- `grounding.status`
- `retrieval.memory_count`
- `trace`

CrispyBrain does not estimate token counts. Missing upstream counts remain explicit unavailable states.

## 8. Safe Validation

Docs-only validation commands:

```bash
git status --short
git describe --tags --always --dirty
rg -n "pre[-]v1|[T]ODO|[F]IXME|placeholder|crispybrain[-]assistant|crispybrain[-]ingest" README.md docs
```

Runtime validation commands, if the local stack is already running:

```bash
node scripts/test-crispybrain-token-contract.js
./scripts/test-crispybrain-v0_9_9_tokens.sh
```

Historical harnesses such as `./scripts/test-crispybrain-v0_8.sh` and `./scripts/test-crispybrain-v0_9_5.sh` remain useful for regression coverage, but their names are historical and are not the current version stamp.
