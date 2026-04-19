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
- `ingest.json`
- `search-by-embedding.json`
- `build-context.json`

Avoid creating new `-v2` or `-fixed` variants for core workflows unless you are deliberately preserving an experiment or migration artifact.

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
- required credentials are still documented
- no local absolute paths or private notes were introduced
- any runtime-sensitive legacy name changes are documented in [legacy-naming-debt.md](legacy-naming-debt.md)

## Import Helpers

If your local environment matches the maintainer Docker setup, `scripts/import-crispybrain-v0_4.sh` can automate imports. Otherwise, use the n8n UI or your own export/import process.
