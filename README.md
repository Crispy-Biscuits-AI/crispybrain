<p align="center">
  <img src="assets/crispybrain-biscuit.png" alt="CrispyBrain tea biscuit" width="110">
</p>

<h1 align="center">CrispyBrain</h1>

<p align="center">
  Local AI memory, retrieval, and orchestration system
</p>

<p align="center">
  <b>CrispyBrain v0.4</b> · Forked from OpenBrain · Self-hosted · n8n-powered
</p>

CrispyBrain v0.4 is the independently branded fork that carries the project forward, while OpenBrain v0.1 through v0.3 remain preserved in `/Users/elric/repos/openbrain` for historical continuity.

The original OpenBrain concept introduced by Nate Jones inspired the early architecture. This fork preserves that lineage while giving the working system its own crisp identity.

- Reference: [Nate Jones OpenBrain video](https://www.youtube.com/watch?v=2JiMmye2ezg&utm_source=chatgpt.com)

## What v0.4 Changes <img src="assets/biscuit-emoji.png" width="18" valign="middle">

- Rebrands the working system from OpenBrain to CrispyBrain
- Simplifies workflow names by dropping the `openbrain-` prefix
- Changes the assistant webhook from `/webhook/openbrain-assistant` to `/webhook/assistant`
- Imports CrispyBrain workflows into `Personal -> CrispyBrain v0.4`
- Adds a local GUI with `dark polarized` and `light polarized` themes
- Preserves the existing Postgres schema and table names, including `openbrain_chat_turns`

## Repo Notes

- The active workflow export filenames now match the concise imported workflow names under `workflows/`, such as `assistant.json`, `ingest.json`, and `build-context.json`.
- The internal workflow `id` and `name` fields are the new concise CrispyBrain names such as `assistant`, `ingest`, and `build-context`.
- OpenBrain and CrispyBrain are meant to coexist side-by-side in the same n8n instance.

## Active Entrypoint

- Workflow id/name: `assistant`
- Webhook: `http://localhost:5678/webhook/assistant`
- n8n folder: `CrispyBrain v0.4`
- Local UI: [crispybrain-v0.4-chat.html](/Users/elric/repos/crispybrain/docs/crispybrain-v0.4-chat.html)

Example smoke request:

```bash
curl -X POST "http://localhost:5678/webhook/assistant" \
  -H "Content-Type: application/json" \
  -d '{"message":"What is CrispyBrain?"}'
```

## Import

Run:

```bash
./scripts/import-crispybrain-v0_4.sh
```

This script:

1. applies `sql/crispybrain-v0_4-upgrade.sql`
2. ensures the `CrispyBrain v0.4` folder exists
3. imports every valid workflow export under `workflows/`
4. verifies the imported workflows in that folder no longer use the `openbrain-` prefix
5. verifies the assistant webhook path is `assistant`
6. activates the `assistant` workflow

## Test

Run:

```bash
./scripts/test-crispybrain-v0_4.sh
```

The test verifies:

1. the GUI and docs point to `http://localhost:5678/webhook/assistant`
2. legacy endpoint values migrate to the new assistant endpoint
3. the default theme is `dark polarized`
4. custom endpoints remain untouched
5. the assistant webhook still passes a live smoke request
6. session continuity and invalid-input handling still work

## Docs <img src="assets/biscuit-emoji.png" width="18" valign="middle">

- [crispybrain-v0.4.md](/Users/elric/repos/crispybrain/docs/crispybrain-v0.4.md)
- [HISTORY.md](/Users/elric/repos/crispybrain/docs/HISTORY.md)
- [MIGRATION.md](/Users/elric/repos/crispybrain/docs/MIGRATION.md)
- [crispybrain-webhook-template.md](/Users/elric/repos/crispybrain/docs/crispybrain-webhook-template.md)

## Deferred

- Renaming the existing database table names and SQL schema objects
- Authentication and access control
- Streaming responses
- Deep cleanup of older duplicate experimental workflows already present in n8n

<p align="center">
  <img src="assets/biscuit-emoji.png" alt="CrispyBrain biscuit emoji" width="18">
</p>
