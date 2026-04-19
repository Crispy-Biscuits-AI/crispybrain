# Local Demo

This is the first intentional local demo surface for CrispyBrain inside the AI Lab.

The primary supported runtime is the Compose-managed lab service `crispybrain-demo-ui` from the sibling `crispy-ai-lab` repo.

## What It Proves

- the UI on `8787` is real
- the backend proxy on `8787` is real
- n8n orchestration is real
- memory retrieval is real
- teacher-style answer generation is real

## Demo Architecture

1. Browser opens `http://localhost:8787`
2. The `crispybrain-demo-ui` container accepts `POST /api/demo/ask`
3. The proxy forwards to the n8n webhook `POST /webhook/crispybrain-demo`
4. The `crispybrain-demo` workflow calls the repo-owned `assistant` webhook path
5. CrispyBrain retrieves memory and returns a structured answer
6. The UI renders the answer, sources, and compact debug info

## Primary Runtime

Clone `crispybrain` and `crispy-ai-lab` as sibling directories, then start the AI Lab services from the lab repo:

```bash
cd ../crispy-ai-lab
cp .env.example .env
docker compose up -d postgres n8n crispybrain-demo-ui
```

Verify the demo container is running:

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

The demo currently assumes the core CrispyBrain workflow path exists in n8n:

- `assistant`

If `assistant` is not active in your local n8n instance, activate it and restart n8n:

```bash
cd ../crispy-ai-lab
docker compose exec -T n8n n8n update:workflow --id=assistant --active=true
docker compose restart n8n
```

The demo wrapper added in this pass is:

- `workflows/crispybrain-demo.json`

The containerized demo UI service is defined in the sibling lab repo:

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

That imports the current public workflow set, including `assistant` and `crispybrain-demo`.

Manual equivalent for the demo wrapper workflow only:

```bash
cd ../crispy-ai-lab
docker compose exec -T n8n sh -lc 'cat > /tmp/crispybrain-demo.json' < ../crispybrain/workflows/crispybrain-demo.json
docker compose exec -T n8n n8n import:workflow --input=/tmp/crispybrain-demo.json
docker compose restart n8n
```

After restart, the demo webhook should be available at:

```text
http://localhost:5678/webhook/crispybrain-demo
```

The wrapper forwards into:

```text
http://localhost:5678/webhook/assistant
```

## Demo UI Themes

Theme control is an intentional supported feature of the demo UI.

Available themes:

- `light`
- `dark`
- `crispy`

Theme behavior:

- first load defaults to `crispy`
- the selector is visible in the UI header
- the current theme is visible in a badge
- the selected theme is stored in localStorage under the demo’s theme key
- missing or invalid stored values fall back to `crispy`
- refresh keeps the selected theme
- restarting the `crispybrain-demo-ui` container does not clear the theme because persistence is client-side
- the stored or default theme is applied before the stylesheet loads, so the page does not flash into the wrong theme first

## Fallback / Dev Runtime

If you need to run the demo proxy outside Docker for local debugging, you can still use the fallback script:

```bash
cd ../crispybrain
python3 scripts/run_demo_server.py
```

That script is now explicitly a fallback/dev utility. The main supported runtime is the Compose service.

## Recommended Demo Question

Use:

```text
How am I planning to build CrispyBrain?
```

With project slug:

```text
alpha
```

That query currently retrieves `alpha` memory rows and produces a grounded answer reliably in the lab.

## Curl Smoke Tests

Direct to the n8n demo webhook:

```bash
curl -sS \
  -H "Content-Type: application/json" \
  -d '{"project_slug":"alpha","question":"How am I planning to build CrispyBrain?"}' \
  http://localhost:5678/webhook/crispybrain-demo | jq .
```

Through the 8787 demo proxy:

```bash
curl -sS \
  -H "Content-Type: application/json" \
  -d '{"project_slug":"alpha","question":"How am I planning to build CrispyBrain?"}' \
  http://localhost:8787/api/demo/ask | jq .
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
  "sources": [
    {
      "title": "openbrain-alpha-plan.txt :: chunk 01"
    }
  ],
  "debug": {
    "workflow": "crispybrain-demo",
    "upstream_workflow": "assistant",
    "teacher_used": true,
    "retrieval_count": 2
  }
}
```

## Honest Failure Modes

- empty question: the UI and proxy return `INVALID_QUESTION`
- empty slug: the demo defaults it to `alpha`
- n8n unavailable: the proxy returns `N8N_UNAVAILABLE`
- no retrieval: the upstream assistant returns a structured error and the UI shows it
- Ollama unavailable: the upstream assistant returns a structured generation/embedding error and the UI shows it

## Troubleshooting

### `Host not found`

If the assistant cannot reach Postgres from n8n, make sure the AI Lab compose stack has the compatibility alias `ai-postgres` on the default network. This pass adds that alias to the lab compose files.

### `The requested webhook "POST crispybrain-demo" is not registered`

Re-import `workflows/crispybrain-demo.json` and restart the n8n service.

### The UI loads but every answer says there is not enough stored memory

Use the recommended question and `alpha` project slug first. The current `alpha` memories are the most reliable demo dataset in this lab.

## Smoke Test Checklist

1. Start the lab stack:

```bash
cd ../crispy-ai-lab
docker compose up -d postgres n8n crispybrain-demo-ui
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
  http://localhost:8787/api/demo/ask | jq .
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

7. Browser-check theme persistence:
- open `http://localhost:8787`
- confirm a fresh load starts in `crispy`
- switch from `crispy` to `dark`
- confirm the theme badge updates
- refresh the page and confirm the selected theme remains

8. Browser-check container restart resilience:

```bash
cd ../crispy-ai-lab
docker compose restart crispybrain-demo-ui
```

- reload `http://localhost:8787`
- confirm the previously selected theme still applies

9. Browser-check invalid-theme fallback:
- set `localStorage["crispybrain-demo-theme"] = "banana"` in the browser console
- reload `http://localhost:8787`
- confirm the UI falls back to `crispy`
