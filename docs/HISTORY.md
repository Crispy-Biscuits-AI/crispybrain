# History

## Before This Repo

- Earlier local experiments established the basic pattern of a webhook-driven assistant backed by Postgres, embeddings, and retrieval.
- This repository starts the standalone public CrispyBrain product line.

## CrispyBrain v0.4

- establishes the current public CrispyBrain repo identity
- uses `assistant` as the main webhook entrypoint
- keeps some runtime-sensitive compatibility names, such as `openbrain_chat_turns`, to avoid a risky migration during initial release hardening
- includes the workflow exports, local UI, SQL, and helper scripts that define the present technical path
