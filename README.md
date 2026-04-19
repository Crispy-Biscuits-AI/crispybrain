<p align="center">
  <img src="assets/crispybrain-biscuit.png" alt="CrispyBrain tea biscuit" width="220">
</p>

<h1 align="center">CrispyBrain</h1>

<p align="center">
  An experimental local-first memory assistant with a real demo UI, real n8n workflow path, and a self-hosted lab runtime.
</p>

`crispybrain` is the public product/demo repo for CrispyBrain.

It is the place to understand the current demo surface, the workflow shape, the public product direction, and the real local path that ends at `http://localhost:8787` when run through the sibling `crispy-ai-lab` repo.

## Current State

- early, real, build-in-public demo
- local-first and self-hosted
- good for showing the current product slice honestly
- not production-ready
- not a turnkey hosted platform

## What The Demo Currently Proves

The current demo is a narrow but real vertical slice:

- the UI on port `8787` is real
- `POST /api/demo/ask` is real
- the request reaches n8n through `crispybrain-demo`
- the demo wrapper forwards into the `assistant` workflow
- the answer is grounded in retrieved memory rather than mocked text

The current documented path is:

```text
localhost:8787
-> /api/demo/ask
-> n8n crispybrain-demo
-> assistant
-> retrieval + grounded answer
```

## Quickstart

The most believable public quickstart currently uses both repos together.

1. Clone both repos as sibling directories.

```bash
git clone <crispybrain-repo-url> crispybrain
git clone <crispy-ai-lab-repo-url> crispy-ai-lab
```

2. Configure and start the lab runtime.

```bash
cd crispy-ai-lab
cp .env.example .env
docker compose up -d postgres n8n crispybrain-demo-ui
```

3. Import the current workflow set from this repo into the running n8n container.

```bash
WORKFLOW_DIR=../crispybrain/workflows \
CONFIRM_IMPORT=I_UNDERSTAND \
scripts/workflows/import-exported-into-docker.sh
```

4. In n8n, create a Postgres credential named `Postgres account`, then activate `assistant` and `crispybrain-demo`.

5. Open the demo UI.

```text
http://localhost:8787
```

6. Use:

- project slug: `alpha`
- question: `How am I planning to build CrispyBrain?`

Success currently looks like:

- the page loads on `localhost:8787`
- the theme selector is available
- the response includes an answer and source rows
- the `debug` block shows the request passed through the demo workflow path

## Themes

The demo UI currently supports:

- `light`
- `dark`
- `crispy`

`crispy` is the default theme.

The selected theme is stored client-side so it survives reloads and container restarts.

Because CrispyBrain is being built in public, the demo also includes intentionally subtle support/contact links in the footer.
They are optional and kept low-prominence so the UI still reads as a demo first.

## Repo Layout

- `demo/`: the current demo UI and local proxy server
- `workflows/`: exported n8n workflow JSON, including `assistant` and `crispybrain-demo`
- `sql/`: checked-in SQL needed by the current assistant path
- `scripts/`: maintainer and local helper scripts
- `docs/`: setup, demo, scope, and technical notes
- `assets/`: public artwork used by the demo and docs

## Relationship To `crispy-ai-lab`

`crispy-ai-lab` is the sibling runtime repo.

Use it when you want:

- the Docker Compose stack
- local Postgres and n8n services
- the `crispybrain-demo-ui` service on `8787`
- the practical operator/runtime setup for the demo

Use this repo when you want:

- the public demo surface
- the current product-facing workflow path
- demo docs and product positioning

## Manual Steps And Honest Limitations

This repo is public-ready, not fully turnkey.

Current manual/runtime assumptions:

- you still need to copy `.env.example` to `.env` in `crispy-ai-lab`
- Ollama must already be running on the host
- workflows must be imported into n8n
- credentials must be created in n8n manually
- the current workflow set still assumes a credential named `Postgres account`
- the current demo dataset is strongest for project slug `alpha`

Compatibility caveats that remain true on purpose:

- some underlying table names and stored source titles may still contain earlier `openbrain-*` names
- that legacy naming is documented and should not be casually renamed in this hardening pass

## Docs

- [Local Demo](docs/demo-local.md)
- [Operator Quickstart](docs/operator-quickstart.md)
- [Minimal Setup](docs/setup-minimal.md)
- [Workflow Sync](docs/workflow-sync.md)
- [Public Scope](docs/public-scope.md)
- [Private Boundary Notes](docs/private-boundary-notes.md)
- [Legacy Naming Debt](docs/legacy-naming-debt.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)

## License

[MIT](LICENSE)
