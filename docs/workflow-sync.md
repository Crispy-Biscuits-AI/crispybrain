# Workflow Sync

Current version: `v1.0.0-14-g59bd5dc`

The workflow exports in `workflows/` are snapshots of n8n workflows. n8n is still a live editing surface, so exported JSON and runtime state can drift unless changes are re-exported intentionally.

## Canonical Current Files

The current product path uses:

- `workflows/assistant.json`
- `workflows/ingest.json`
- `workflows/crispybrain-demo.json`
- `workflows/auto-ingest-watch.json` when file-drop ingest is enabled

Historical/helper workflow exports may remain in `workflows/`, including `insert-embedding-fixed*.json` variants. Do not treat every file in that directory as an active entrypoint.

## Current Public Webhooks

- `POST /webhook/assistant`
- `POST /webhook/ingest`
- `POST /webhook/crispybrain-demo`

Legacy `crispybrain-assistant`, `crispybrain-ingest`, and `crispybrain-auto-ingest-watch` names are historical/retired duplicate names in the current docs. If they exist in a local n8n database, verify whether they are inactive before relying on them.

## Import

For the maintainer reference runtime:

```bash
cd /Users/elric/repos/crispy-ai-lab
WORKFLOW_DIR=../crispybrain/workflows \
CONFIRM_IMPORT=I_UNDERSTAND \
scripts/workflows/import-exported-into-docker.sh
```

After import, create or remap the n8n credential named:

```text
Postgres account
```

Then activate the workflows you intend to use.

## Export Discipline

When a workflow changes in n8n and should become repo state:

1. Export the workflow JSON from n8n.
2. Replace the matching stable file under `workflows/`.
3. Verify webhook paths, credential names, Ollama URLs, and Postgres nodes.
4. Update README/docs if operator behavior changed.
5. Commit the workflow export and doc update together.

Do not create new `-v2` or `-fixed` core workflow names unless you are deliberately preserving a historical artifact.

## Before Commit

Verify:

- no credentials or secrets are embedded in exports
- the assistant entrypoint is still `/webhook/assistant`
- the ingest entrypoint is still `/webhook/ingest`
- the demo entrypoint is still `/webhook/crispybrain-demo`
- watcher paths, if active, still point at `/home/node/.n8n-files/crispybrain/inbox`
- legacy naming changes are reflected in [legacy-naming-debt.md](legacy-naming-debt.md)
