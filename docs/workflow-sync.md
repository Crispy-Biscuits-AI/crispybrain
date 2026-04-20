# Workflow Sync

## Canonical Workflow Exports

The canonical workflow exports for this repo live in:

```text
workflows/
```

If a workflow changes in n8n and you want that change to be part of the product, export the updated JSON back into this directory.

## Stable Filenames Matter

Use stable filenames for the current product path, such as:

- `assistant.json`
- `crispybrain-demo.json`
- `ingest.json`
- `auto-ingest-watch.json`

Avoid creating new `-v2` or `-fixed` variants for core workflows unless you are deliberately preserving an experiment or migration artifact.

The canonical runtime entrypoints are:

- required: `assistant`
- required: `ingest`
- required: `crispybrain-demo`
- optional: `auto-ingest-watch`

Retired duplicate in the current audited runtime:

- `crispybrain-auto-ingest-watch`, moved to `Personal -> CrispyBrain Archive` and left inactive
- `crispybrain-assistant`, moved to `Personal -> CrispyBrain Archive` and left inactive
- `crispybrain-ingest`, moved to `Personal -> CrispyBrain Archive` and left inactive

If you use n8n folders, keep that runtime grouped under `Personal -> CrispyBrain`.

Folder placement is organizational only. Runtime behavior comes from the workflow `active` state plus the webhook or trigger path that callers hit.

## How To Verify The Active Runtime

Check at least these things in n8n:

- `assistant`, `ingest`, and `crispybrain-demo` are active
- `crispybrain-demo` still calls `/webhook/assistant`
- `crispybrain-assistant`, `crispybrain-ingest`, and `crispybrain-auto-ingest-watch` are inactive
- any remaining client still hitting `/webhook/crispybrain-assistant` or `/webhook/crispybrain-ingest` is updated to the canonical public endpoints

The audit-friendly workflow list query used in this repo is:

```sql
SELECT w.name, w.active, COALESCE(f.name, '') AS folder_name
FROM workflow_entity w
LEFT JOIN folder f ON f.id = w."parentFolderId"
WHERE w.name IN (
  'assistant',
  'crispybrain-assistant',
  'ingest',
  'crispybrain-ingest',
  'auto-ingest-watch',
  'crispybrain-auto-ingest-watch',
  'crispybrain-demo'
)
ORDER BY w.name;
```

## Recommended Sync Process

1. Make the workflow change in n8n.
2. Export the updated workflow JSON.
3. Save it back into the matching file under `workflows/`.
4. Check that credential names, webhook paths, and model endpoints still match the docs.
5. Update `README.md` or `docs/setup-minimal.md` if the operator story changed.

## Before Commit

Verify at least these things:

- workflow name and filename still match
- the assistant entrypoint is still `/webhook/assistant`
- the ingest entrypoint is still `/webhook/ingest`
- the demo entrypoint is still `/webhook/crispybrain-demo`
- required credentials are still documented
- no local absolute paths or private notes were introduced
- any runtime-sensitive legacy name changes are documented in [legacy-naming-debt.md](legacy-naming-debt.md)

## Import Helpers

If your local environment matches the maintainer Docker setup, `scripts/import-crispybrain-v0_4.sh` can automate imports. Otherwise, use the n8n UI or your own export/import process.
