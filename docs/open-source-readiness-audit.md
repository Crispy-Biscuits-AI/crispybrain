# Open Source Readiness Audit

Current version: `v1.0.0-14-g59bd5dc`

Status: refreshed as a current documentation note. Older statements about untracked files or a pre-release pass were removed because they were stale.

## Ready Public Surface

- Real workflow exports live in `workflows/`.
- The demo UI and proxy server live in `demo/`.
- Setup, ingest, workflow sync, trust, retrieval, and compatibility docs live in `docs/`.
- The repo has an MIT `LICENSE`.
- `.env.example` documents required environment names without exposing live secrets.

## Still Not Turnkey

- n8n credentials are configured manually after import.
- The workflow exports expect the n8n credential name `Postgres account`.
- Ollama must already be reachable from n8n at `http://host.docker.internal:11434`.
- The checked-in SQL does not fully bootstrap every table used by all workflow paths from a blank database.
- Some behavior depends on the sibling `crispy-ai-lab` reference runtime wiring.

## Public Boundary

Do not publish:

- private runtime exports
- `.env` values
- customer data
- local credential material
- archived runtime backups
- production workflow exports not already intended for this repo

## Current Readiness

The repo is suitable as a technical public product repo for operators comfortable with n8n, Postgres, Ollama, Docker, and manual workflow import. It should not be described as a polished hosted service or one-command installer.
