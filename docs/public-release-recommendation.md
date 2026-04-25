# Public Release Recommendation

Current version: `v1.0.0-14-g59bd5dc`

## Recommendation

CrispyBrain is public-readable as a technical self-hosted memory assistant repo. The strongest public story is still the concrete workflow path: ingest notes, store memory in Postgres with pgvector, retrieve relevant context, and answer through n8n workflows backed by Ollama.

## Release Caveats

- It is not a turnkey installer.
- n8n credential setup is manual.
- The reference runtime lives in the sibling `crispy-ai-lab` repo.
- Current docs intentionally preserve compatibility notes for `openbrain_*` names.
- Complete historical version reconstruction is not possible from local tags alone.

## Suggested Description

CrispyBrain is a local-first, self-hosted project memory assistant built with n8n, Postgres/pgvector, and Ollama. It focuses on inspectable retrieval, sources, grounding, trace output, and explicit uncertainty.
