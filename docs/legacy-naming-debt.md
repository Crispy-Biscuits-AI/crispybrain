# Legacy Naming Debt

This repo still carries some earlier internal naming for compatibility. That debt is documented here so it does not get mistaken for the public product identity.

## Runtime-Sensitive Debt

### `openbrain_chat_turns`

Where it appears:

- `sql/crispybrain-v0_4-upgrade.sql`
- `workflows/assistant.json`
- `scripts/test-crispybrain-v0_4.sh`

Why it matters:

- the assistant workflow reads and writes this table for session continuity
- renaming it casually would break the live workflow path unless the SQL, workflow JSON, and any existing data are migrated together

Recommendation:

- do not rename this table in a public release hardening pass
- handle it later as a staged compatibility migration

### Credential Name `Postgres account`

Where it appears:

- several workflow exports in `workflows/`

Why it matters:

- the imported workflows expect that credential name in n8n

Recommendation:

- keep documenting the required name for now
- if you change it later, update the exports and setup docs together

## Cosmetic Or Runtime-Adjacent Debt

### Older `openbrain-*` migration references

Where it appears:

- `docs/MIGRATION.md`
- legacy localStorage migration behavior in `docs/crispybrain-v0.4-chat.html`

Why it matters:

- these references exist to help older local installs migrate cleanly

Recommendation:

- keep them while older migrations still matter
- do not let them dominate the README or public product story

### Default container names in helper scripts

Where it appears:

- `scripts/crispybrain-test-harness.sh`

Examples:

- `ai-n8n`
- `ai-postgres`

Why it matters:

- these are local helper defaults, not the public product identity

Recommendation:

- leave them as helper-script defaults for now
- treat them as local environment assumptions, not branding

## Safe Future Migration Sequence

1. export and back up the current workflows
2. create a new session-turn table with the desired CrispyBrain-native name
3. migrate data from `openbrain_chat_turns`
4. update the assistant workflow and tests to dual-read or cut over
5. validate session continuity in a staging environment
6. remove old references only after successful cutover

## What Not To Rename Casually

- database table names used by active workflows
- credential names embedded in workflow exports
- webhook paths that clients may already call
