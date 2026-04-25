# Release Checklist

Current version: `v1.0.0-14-g59bd5dc`

Use this checklist before publishing docs or cutting a release-like branch.

## Hygiene

- `git status --short` is clean except intended docs/workflow changes
- no `.env` file is staged
- no secrets, tokens, or live credential values are in docs
- no archived runtime backups or private exports are staged
- README and [current-state.md](current-state.md) agree on the version stamp

## Docs

- README says `Current version: v1.0.0-14-g59bd5dc`
- historical `v0.x` docs are clearly treated as historical notes
- setup docs still match the current workflow entrypoints
- trust/retrieval docs do not claim hidden confidence scores or invented token counts
- changelog entries are backed by Git tags or commit timestamps

## Runtime Smoke Checks

Only run these when the local runtime is already intended to be active:

```bash
curl -sS \
  -H "Content-Type: application/json" \
  -d '{"message":"How am I planning to build CrispyBrain?","project_slug":"alpha"}' \
  http://localhost:5678/webhook/assistant | jq '{ok,usage,grounding,trace}'
```

```bash
node scripts/test-crispybrain-token-contract.js
./scripts/test-crispybrain-v0_9_9_tokens.sh
```

## Final Docs Checks

```bash
rg -n "pre[-]v1|[T]ODO|[F]IXME|placeholder|crispybrain[-]assistant|crispybrain[-]ingest" README.md docs
rg -n "OPENAI[_]API[_]KEY|API[_]KEY|[T]OKEN|[S]ECRET|[P]ASSWORD|PRIVATE[_]KEY" README.md docs CHANGELOG.md
```
