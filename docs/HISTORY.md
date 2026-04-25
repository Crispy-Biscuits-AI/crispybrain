# History

Current version: `v1.0.0-14-g59bd5dc`

This file is a concise historical orientation. For verifiable tag and commit history, use [../CHANGELOG.md](../CHANGELOG.md).

## Before CrispyBrain

- Early local experiments used the OpenBrain name and established the pattern of a webhook-driven assistant backed by Postgres, embeddings, and retrieval.
- CrispyBrain became the public product identity at the `v0.4` line.

## Public CrispyBrain Line

- `v0.4`: public repo identity, local UI, workflow exports, SQL migration material, and compatibility-sensitive `openbrain_chat_turns` retention.
- `v0.5` to `v0.8`: observability, validation, memory quality tooling, grounding, and evaluation harnesses.
- `v0.9.x`: retrieval calibration, conflict handling, token-usage surfacing, source quality, source independence, and trace/answer presentation improvements.
- `v1.0.0`: the only local Git tag present during this docs refresh.
- `v1.0.0-14-g59bd5dc`: requested docs stamp for the current refresh.

## Compatibility Note

Some `openbrain-*` names remain in historical docs, table names, project slugs, and migration notes. They are compatibility/history references and should not be renamed casually without a coordinated workflow, SQL, and data migration.
