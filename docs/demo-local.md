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
2. The demo server on `8787` serves `GET /api/projects`, `POST /api/projects`, and `DELETE /api/projects/<project-slug>` from the repo inbox
3. The same server accepts `POST /api/demo/ask`
4. The proxy forwards to the n8n webhook `POST /webhook/crispybrain-demo`
5. The `crispybrain-demo` workflow calls the repo-owned `assistant` webhook path
6. CrispyBrain retrieves memory and returns a structured answer
7. The UI renders the answer, sources, and traceable retrieval signals

## Primary Runtime

Clone `crispybrain` and `crispy-ai-lab` as sibling directories, then start the AI Lab services from the lab repo:

```bash
cd ../crispy-ai-lab
cp .env.example .env
../crispybrain/scripts/set-version-env.sh up -d postgres n8n crispybrain-demo-ui
```

That wrapper now injects the repo inbox bind mount into `crispybrain-demo-ui`:

- host source: `/Users/elric/repos/crispybrain/inbox`
- container target: `/app/inbox`

If you have changed files in `../crispybrain/demo/` or `../crispybrain/assets/`, rebuild the UI service so port `8787` serves the updated image contents:

```bash
../crispybrain/scripts/set-version-env.sh up -d --build crispybrain-demo-ui
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

That script remains the repo-local fallback/dev path.
The Compose service also supports direct inbox project management now when it is started through `scripts/set-version-env.sh`, because the wrapper injects the repo inbox mount for `crispybrain-demo-ui`.

## Project API

The demo server now treats the repo inbox as the source of truth for projects in both supported runtime paths:

- the repo-local fallback script
- the Compose-managed `crispybrain-demo-ui` service when started through `scripts/set-version-env.sh`

- `GET /api/projects` returns the current immediate subfolders under `/Users/elric/repos/crispybrain/inbox/`
- `POST /api/projects` creates `inbox/<project-slug>/` when the slug is valid and available
- `DELETE /api/projects/<project-slug>` removes that inbox folder when the slug is valid and present
- the UI selector reloads from that API instead of using hardcoded project names
- creating a project from the UI reloads the selector and auto-selects the created slug
- deleting a project from the UI removes it from both the filesystem and the selector immediately
- when no inbox projects exist, the UI renders a safe empty state, disables query submission, and keeps the create flow available

Create validation rules:

- slugs are trimmed before validation
- slugs must start with a letter or number
- the remaining characters may only be letters, numbers, dots, underscores, and hyphens
- empty and whitespace-only input returns `400`
- duplicate slugs return `409`
- invalid or escaping/path-traversal input returns `400`
- validation failures do not partially create `inbox/<project-slug>/`

Response shapes:

- `GET /api/projects` returns `{ "projects": [...], "default_project_slug": "..." }`
- successful `POST /api/projects` returns the same selector payload plus `ok`, `created_project_slug`, and `selected_project_slug`
- successful `DELETE /api/projects/<project-slug>` returns the same selector payload plus `ok` and `deleted_project_slug`
- validation failures return `ok = false` and an `error` object with a stable `code` and user-facing `message`

## Recommended Query

Use:

```text
How am I planning to build CrispyBrain?
```

With project slug:

```text
alpha
```

The top control area now renders as one larger parent pane with three visible sub-panes on desktop widths:

- `Query context`: the visible project selector and active queried context
- `Ask a question`: a larger multiline query entry area and `Run query` in the primary center pane
- `Project management`: a delete-target pulldown plus `Delete Project`, new project slug input, and `Create Project`

The visible project selector in the `Query context` pane now reflects the current immediate subfolders under `/Users/elric/repos/crispybrain/inbox/`.
If `alpha` exists, the selector chooses it by default on load.
The `Create Project` control makes a new inbox folder directly from the UI and then selects it automatically.
The `Delete Project` control removes the explicitly selected delete target after confirmation and then refreshes the selector state immediately.
The `Ask a question` pane keeps query submission separate while still using the currently selected project context and repeating that context near the query input.
If the inbox is temporarily empty, the UI shows a no-projects message, disables query submission safely, and keeps project creation available.
The answer panel now places the direct answer above `Why this answer`, while sources and trace behavior remain unchanged.
That query currently retrieves `alpha` memory rows reliably in the lab and exercises the explanation, sources, and trace panes even when grounding stays weak.
The answer control row also includes `Export MD (Full)` and `Export MD (Social)`, which copy a markdown share snippet from the currently rendered UI state without downloading a file or changing the query flow.

Example full export:

```md
# 🧠 CrispyBrain Q&A

## ❓ Question
Who is Darth Vader?

## ✅ Answer
Darth Vader is Anakin Skywalker, a central character in Star Wars.

## 🧩 Why This Answer
- This answer is based on limited evidence from 1 project memory source. Some details may be incomplete.

## 📚 Sources
- star-wars-notes.md (chunk 01) — "Anakin Skywalker became Darth Vader."

---
Shared via **CrispyBrain (local-first AI memory system)**
```

## Transparency In `v0.9.9`

The local UI now centers the answer while making sources and trace signals easier to inspect.
The current demo build keeps the explanation layer above the raw trace without removing the existing panes or changing the layout grid.
The demo server also exposes `GET /meta`, which returns JSON with the current `version`, `runtime`, and short `commit` hash from the same runtime helpers.
Token usage in this surface reflects live Ollama generation counts when the upstream answer path reports them. The UI does not backfill estimates when those counts are absent.

## Version Handling

Docker containers for this demo image do not include `.git` metadata, so version lookup must be injected from the host when you start the Compose-managed UI service.

Use the wrapper from the sibling lab repo:

```bash
cd ../crispy-ai-lab
../crispybrain/scripts/set-version-env.sh up -d crispybrain-demo-ui
```

If you have changed the UI files and need a rebuild, use:

```bash
cd ../crispy-ai-lab
../crispybrain/scripts/set-version-env.sh up -d --build crispybrain-demo-ui
```

The wrapper resolves the host checkout version, exports `CRISPYBRAIN_APP_VERSION`, and keeps the containerized footer and `GET /meta` output aligned with the repo version that launched the service.

The version resolution order is:

1. `CRISPYBRAIN_APP_VERSION`
2. `git describe --tags --always`
3. `git rev-parse --short HEAD`
4. `unknown-version (docker)` when the container has neither injected version data nor git metadata

The footer and `GET /meta` both use that same resolved version string, so the containerized UI keeps the latest footer links without falling back to a stale hardcoded label or duplicating the `(docker)` suffix.

When retrieval support is available, the UI now shows:

- an answer panel with the current response
- an explanation layer at the top of the answer panel titled `Why this answer`
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
- weak support still renders a visible uncertainty note, but it now stays in `Why this answer` so the `Answer` pane can show only the direct grounded answer when one exists
- unsupported detail prompts keep the direct answer pane concise, for example `Project memory does not mention Darth Vader's cape being pink.`, while retrieval-limit and partial-context wording stays in `Why this answer`
- display-only answer cleanup preserves canonical proper-name capitalization from the question and visible source snippets, so normalized matching text does not leak into the rendered answer

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

Through the 8787 project API:

```bash
curl -sS http://localhost:8787/api/projects | jq .

curl -sS \
  -H "Content-Type: application/json" \
  -d '{"project_slug":"demo-docs-smoke"}' \
  http://localhost:8787/api/projects | jq .

curl -sS \
  -X DELETE \
  http://localhost:8787/api/projects/demo-docs-smoke | jq .
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
- empty or whitespace-only project creation: `POST /api/projects` returns `EMPTY_PROJECT_SLUG`
- duplicate project creation: `POST /api/projects` returns `PROJECT_ALREADY_EXISTS`
- invalid project creation: `POST /api/projects` returns `INVALID_PROJECT_SLUG`
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
../crispybrain/scripts/set-version-env.sh up -d postgres n8n crispybrain-demo-ui
```

If the browser still shows an older UI after repo changes, rebuild the UI service explicitly:

```bash
../crispybrain/scripts/set-version-env.sh up -d --build crispybrain-demo-ui
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
