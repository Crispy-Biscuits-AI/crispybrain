# Migration

## Workflow Name Changes

| Old imported name | New imported name |
| --- | --- |
| `openbrain-ingest` | `ingest` |
| `openbrain-build-context` | `build-context` |
| `openbrain-answer-from-memory` | `answer-from-memory` |
| `openbrain-auto-ingest-watch` | `auto-ingest-watch` |
| `openbrain-validation-and-errors` | `validation-and-errors` |
| `openbrain-project-memory` | `project-memory` |
| `openbrain-assistant` | `assistant` |
| any other `openbrain-*` workflow | same name without the `openbrain-` prefix |

## Webhook Change

| Old path | New path |
| --- | --- |
| `http://localhost:5678/webhook/openbrain-assistant` | `http://localhost:5678/webhook/assistant` |

## Folder Change

| Old folder | New folder |
| --- | --- |
| `Personal -> OpenBrain v0.3` | `Personal -> CrispyBrain v0.4` |

## LocalStorage Migration

| Old key | New key |
| --- | --- |
| `openbrain_endpoint` | `crispybrain_endpoint` |
| `openbrain_session_id` | `crispybrain_session_id` |
| `openbrain_project_slug` | `crispybrain_project_slug` |
| `openbrain_theme` | `crispybrain_theme` |

Behavior:

- the legacy stored assistant endpoint `http://localhost:5678/webhook/openbrain-assistant` auto-migrates to `http://localhost:5678/webhook/assistant`
- the stale incomplete endpoint `http://localhost:5678/webhook` also auto-migrates to `http://localhost:5678/webhook/assistant`
- custom user-entered endpoints are preserved
- active workflow export filenames now also use the concise CrispyBrain forms, such as `workflows/assistant.json` and `workflows/build-context.json`
