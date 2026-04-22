# Local UI

This is the first intentional local UI surface for CrispyBrain inside the AI Lab.

The primary supported runtime is the Compose-managed lab service `crispybrain-demo-ui` from the sibling `crispy-ai-lab` repo.

The canonical CrispyBrain ingest inbox now lives in this repo at `/Users/elric/repos/crispybrain/inbox/<project-slug>/`.

## What It Proves

- the UI on `8787` is real
- the backend proxy on `8787` is real
- n8n orchestration is real
- memory retrieval is real
- source-backed answer generation is real
- grounding visibility is real

## UI Architecture

1. Browser opens `http://localhost:8787`
2. The `crispybrain-demo-ui` container accepts `POST /api/demo/ask`
3. The proxy forwards to the n8n webhook `POST /webhook/crispybrain-demo`
4. The `crispybrain-demo` workflow calls the repo-owned `assistant` webhook path
5. CrispyBrain retrieves memory and returns a structured answer
6. The UI renders the answer, sources, and traceable retrieval signals

## Primary Runtime

Clone `crispybrain` and `crispy-ai-lab` as sibling directories, then start the AI Lab services from the lab repo:

```bash
cd ../crispy-ai-lab
cp .env.example .env
docker compose up -d postgres n8n crispybrain-demo-ui
```

If you have changed files in `../crispybrain/demo/` or `../crispybrain/assets/`, rebuild the UI service so port `8787` serves the updated image contents:

```bash
docker compose up -d --build crispybrain-demo-ui
```

Verify the UI container is running:

```bash
docker compose ps crispybrain-demo-ui
```

Open:

```text
http://localhost:8787
```

## Required Services

You need the AI Lab runtime from the sibling `crispy-ai-lab` repo:

- Postgres
- n8n
- host-side Ollama reachable from n8n

The verified canonical workflow set in n8n is:

- required: `assistant`
- required: `ingest`
- required: `crispybrain-demo`
- optional: `auto-ingest-watch`

Retired legacy endpoints after the hard cutover:

- `crispybrain-assistant`
- `crispybrain-ingest`

Any remaining client still using `/webhook/crispybrain-assistant` or `/webhook/crispybrain-ingest` must be updated to the canonical public endpoints.

The live UI path depends directly on:

- `assistant`
- `crispybrain-demo`

If the required workflows are not active in your local n8n instance, activate them and restart n8n:

```bash
cd ../crispy-ai-lab
docker compose exec -T n8n n8n update:workflow --id=assistant --active=true
docker compose exec -T n8n n8n update:workflow --id=ingest --active=true
docker compose exec -T n8n n8n update:workflow --id=crispybrain-demo --active=true
docker compose restart n8n
```

The UI wrapper workflow added in this pass is:

- `workflows/crispybrain-demo.json`

The containerized UI service is defined in the sibling lab repo:

- `../crispy-ai-lab/docker-compose.yml`

The container reaches the backend through an explicit environment variable in that Compose service:

- `CRISPYBRAIN_DEMO_WEBHOOK_URL=http://n8n:5678/webhook/crispybrain-demo`

If you use the fallback local script instead, the default upstream becomes:

- `http://localhost:5678/webhook/crispybrain-demo`

## One-Time n8n Import

Recommended import path:

```bash
cd ../crispy-ai-lab
WORKFLOW_DIR=../crispybrain/workflows \
CONFIRM_IMPORT=I_UNDERSTAND \
scripts/workflows/import-exported-into-docker.sh
```

That imports the current public workflow set, including `assistant`, `ingest`, `crispybrain-demo`, and the canonical watcher export `auto-ingest-watch`.

If you organize the workflows in n8n folders, the recommended home is `Personal -> CrispyBrain`.

Folder placement is organizational only. The real live path is whichever workflows are active and which webhook paths your caller is configured to hit.

## Canonical Inbox Path

Use the repo-owned inbox path for local note drops:

```text
/Users/elric/repos/crispybrain/inbox/<project-slug>/
```

For the default UI project:

```bash
mkdir -p /Users/elric/repos/crispybrain/inbox/alpha
```

Place plain `.txt` notes in that folder before querying the UI with the matching `project_slug`.

Current verified local runtime:

- `auto-ingest-watch` is active in n8n
- it polls `/home/node/.n8n-files/crispybrain/inbox` inside the container
- the current bind mount points there from `/Users/elric/repos/crispybrain/inbox`
- a real file drop into `/Users/elric/repos/crispybrain/inbox/alpha/` now appears at the watched container path and flows into canonical `/webhook/ingest`

Manual equivalent for the UI wrapper workflow only:

```bash
cd ../crispy-ai-lab
docker compose exec -T n8n sh -lc 'cat > /tmp/crispybrain-demo.json' < ../crispybrain/workflows/crispybrain-demo.json
docker compose exec -T n8n n8n import:workflow --input=/tmp/crispybrain-demo.json
docker compose restart n8n
```

After restart, the UI webhook should be available at:

```text
http://localhost:5678/webhook/crispybrain-demo
```

The wrapper forwards into:

```text
http://localhost:5678/webhook/assistant
```

To verify the current live path in n8n, confirm both of these are true:

- `crispybrain-demo` is active and exposes `/webhook/crispybrain-demo`
- the `Call Assistant Workflow` node inside `crispybrain-demo` targets `/webhook/assistant`
- `/webhook/crispybrain-assistant` and `/webhook/crispybrain-ingest` are no longer active
- if you are testing automatic ingest, the same dropped file is visible at `/home/node/.n8n-files/crispybrain/inbox/<project-slug>/` inside the n8n container

## UI Themes

Theme control is an intentional supported feature of the UI.

Available themes:

- `light`
- `dark`
- `crispy`

Theme behavior:

- first load defaults to `crispy`
- the selector is visible in the UI header
- the current theme is visible in a badge
- the selected theme is stored in localStorage under the existing theme key
- missing or invalid stored values fall back to `crispy`
- refresh keeps the selected theme
- restarting the `crispybrain-demo-ui` container does not clear the theme because persistence is client-side
- the stored or default theme is applied before the stylesheet loads, so the page does not flash into the wrong theme first

## Fallback / Dev Runtime

If you need to run the UI proxy outside Docker for local debugging, you can still use the fallback script:

```bash
cd ../crispybrain
python3 scripts/run_demo_server.py
```

That script is now explicitly a fallback/dev utility. The main supported runtime is the Compose service.

## Recommended Query

Use:

```text
How am I planning to build CrispyBrain?
```

With project slug:

```text
alpha
```

The visible project selector in the UI defaults to `alpha` and also exposes `starwars`.
That query currently retrieves `alpha` memory rows reliably in the lab and exercises the explanation, sources, and trace panes even when grounding stays weak.

## Transparency In The Current Demo Build

The local UI now centers the answer while making sources and trace signals easier to inspect.
The current demo build keeps the explanation layer above the raw trace without removing the existing panes or changing the layout grid.
The footer version label is injected from the current repo checkout using `git describe --tags --always`, falling back to `git rev-parse --short HEAD` and then `unknown-version`, and it now appends a runtime context label such as `(local)` or `(docker)` while keeping the existing support and repo links plus the BlueSky, Reddit, and MIT License links without changing the layout grid.
The demo server also exposes `GET /meta`, which returns JSON with the current `version`, `runtime`, and short `commit` hash from the same runtime helpers.
Token usage in this surface reflects live Ollama generation counts when the upstream answer path reports them. The UI does not backfill estimates when those counts are absent.

When retrieval support is available, the UI now shows:

- an answer panel with the current response
- the main answer now renders before the explanation layer, while `Why this answer` stays directly underneath it
- a visible confidence indicator that maps directly from `grounding.status`
- an open-by-default sources panel with visible source cards and previews
- an open-by-default trace panel with live execution, retrieval, and behavior signals when the backend returns them
- the sources panel now includes a `Source summary` block with project slug, answer mode, grounding status, selected-source count, candidate count, and the current grounding note when present
- source cards now prefer the assistant's `selected_sources` list and expose the filename clearly, a chunk label, a short preview, a visible relevance badge, and the existing review/quality/independence metadata when those fields are present in the response
- the trace panel now shows project slug, selected-source count, candidate count, grounding status, answer mode, provider-reported input/output token counts when available, and the current grounding note without hiding the existing layout or footer
- when the upstream answer path does not provide usage, the trace token fields stay at `—` and the API returns `usage.available = false` with `null` token counts instead of estimating them

When support is weak or absent, the workflow stays explicit instead of implying confidence:

- `grounding.status = weak` means the answer has some support but should be treated cautiously
- `grounding.status = none` means no strong supporting memory was retrieved
- `grounding.status = grounded` renders `High confidence`
- `grounding.status = weak` renders `Limited confidence`
- `grounding.status = none` renders `No evidence`
- weak answers also render a visible uncertainty note in the answer panel; when `grounding.note` is present, the UI appends that exact note after the plain-language caution

## Curl Smoke Tests

Direct to the n8n UI webhook:

```bash
curl -sS \
  -H "Content-Type: application/json" \
  -d '{"project_slug":"alpha","question":"How am I planning to build CrispyBrain?"}' \
  http://localhost:5678/webhook/crispybrain-demo | jq '{ok,answer,usage,trace}'
```

Through the 8787 UI proxy:

```bash
curl -sS \
  -H "Content-Type: application/json" \
  -d '{"project_slug":"alpha","question":"How am I planning to build CrispyBrain?"}' \
  http://localhost:8787/api/demo/ask | jq '{ok,answer,usage,trace}'
```

Check the containerized UI is serving the page:

```bash
curl -sS http://localhost:8787 | sed -n '1,20p'
```

## Expected Successful Shape

```json
{
  "ok": true,
  "project_slug": "alpha",
  "question": "How am I planning to build CrispyBrain?",
  "answer": "...",
  "usage": {
    "provider": "ollama",
    "source": "generation",
    "available": true,
    "input_tokens": 42,
    "output_tokens": 27,
    "total_tokens": 69,
    "reason": null
  },
  "grounding": {
    "status": "weak",
    "note": "...",
    "supporting_source_count": 2,
    "reviewed_source_count": 2
  },
  "sources": [
    {
      "id": 123,
      "title": "openbrain-alpha-plan.txt :: chunk 01",
      "trust_band": "high",
      "similarity": 0.74,
      "chunk_index": 1
    }
  ],
  "trace": {
    "stage": "answer_ready",
    "status": "succeeded",
    "grounding_status": "weak",
    "input_tokens": 42,
    "output_tokens": 27,
    "total_tokens": 69
  }
}
```

## Expected Usage States

- generated answer with provider counts: `usage.available = true`, `usage.reason = null`, numeric `usage.input_tokens` / `usage.output_tokens` / `usage.total_tokens`, and matching token fields in `trace`
- insufficient or skipped generation: `answer_mode = insufficient`, `usage.available = false`, `usage.reason = answer_not_generated`, `null` token fields in the API response, and `—` in the UI trace panel
- successful demo response but missing upstream generation counts: `usage.available = false` with `usage.reason = upstream_usage_missing`; this is explicit missing telemetry, not an estimate

## Honest Failure Modes

- empty question: the UI and proxy return `INVALID_QUESTION`
- blank API slug: the demo proxy defaults it to `alpha`
- n8n unavailable: the proxy returns `N8N_UNAVAILABLE`
- weak retrieval: the upstream assistant can return `grounding.status = weak` with a cautionary note
- no strong retrieval: the upstream assistant can return `grounding.status = none` and no evidence rows
- usage unavailable: `assistant` / `crispybrain-demo` return `usage.available = false` with `null` token fields when answer generation is skipped or Ollama does not report usage
- Ollama unavailable: the upstream assistant returns a structured generation/embedding error and the UI shows it

## Troubleshooting

### `Host not found`

If the assistant cannot reach Postgres from n8n, make sure the AI Lab compose stack has the compatibility alias `ai-postgres` on the default network. This pass adds that alias to the lab compose files.

### `The requested webhook "POST crispybrain-demo" is not registered`

Re-import `workflows/crispybrain-demo.json` and restart the n8n service.

### The UI loads but every answer says there is not enough stored memory

Use the recommended query and `alpha` project slug first. The current `alpha` memories are the most reliable UI dataset in this lab.

## Smoke Test Checklist

1. Start the lab stack:

```bash
cd ../crispy-ai-lab
docker compose up -d postgres n8n crispybrain-demo-ui
```

If the browser still shows an older UI after repo changes, rebuild the UI service explicitly:

```bash
docker compose up -d --build crispybrain-demo-ui
```

2. Verify the service is running:

```bash
docker compose ps crispybrain-demo-ui
```

3. Verify the UI loads:

```bash
curl -sS http://localhost:8787 | sed -n '1,20p'
```

4. Verify the question/answer flow:

```bash
curl -sS \
  -H "Content-Type: application/json" \
  -d '{"project_slug":"alpha","question":"How am I planning to build CrispyBrain?"}' \
  http://localhost:8787/api/demo/ask | jq '{ok,answer,usage,trace}'
```

5. Verify blank project slug defaults to `alpha`:

```bash
curl -sS \
  -H "Content-Type: application/json" \
  -d '{"project_slug":"","question":"What principles guide the alpha project?"}' \
  http://localhost:8787/api/demo/ask | jq .
```

6. Verify empty question validation:

```bash
curl -sS \
  -H "Content-Type: application/json" \
  -d '{"question":""}' \
  http://localhost:8787/api/demo/ask | jq .
```

7. Verify token usage and unavailable handling:

```bash
node scripts/test-crispybrain-token-contract.js
./scripts/test-crispybrain-v0_9_9_tokens.sh
```

Expect the runtime token script to show:

- prompt 1 and prompt 2 both returning `usage.available = true`
- prompt 1 and prompt 2 returning different token counts
- prompt 3 returning `usage.available = false` with `usage.reason = answer_not_generated`

8. Browser-check theme persistence:
- open `http://localhost:8787`
- confirm a fresh load starts in `crispy`
- switch from `crispy` to `dark`
- confirm the theme badge updates
- refresh the page and confirm the selected theme remains

9. Browser-check container restart resilience:

```bash
cd ../crispy-ai-lab
docker compose restart crispybrain-demo-ui
```

- reload `http://localhost:8787`
- confirm the previously selected theme still applies

10. Browser-check invalid-theme fallback:
- set `localStorage["crispybrain-demo-theme"] = "banana"` in the browser console
- reload `http://localhost:8787`
- confirm the UI falls back to `crispy`
