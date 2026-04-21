# Release Checklist

## Hygiene

- confirm no secrets or secret-like values are tracked
- confirm no absolute local machine paths remain in public docs
- confirm no accidental backup or junk files are staged
- confirm `.env.example` still matches the documented setup

## Docs

- README describes CrispyBrain as the product
- README states that token usage reflects real model execution when available and stays explicitly unavailable when it is not
- operator quickstart still matches the actual workflow/runtime path
- setup docs still describe the required dependencies honestly
- public scope and private boundary docs still match the intended repo boundary
- legacy naming debt doc still reflects the current runtime reality
- no public doc still implies mocked, fixed, stale, or estimated token counts

## Setup Verification

- import the stable workflows into a clean-ish n8n instance
- verify a Postgres credential named `Postgres account` works
- verify Ollama access and required models
- run a smoke request against `/webhook/assistant`
- run the token-usage contract and runtime checks (`node scripts/test-crispybrain-token-contract.js` and `./scripts/test-crispybrain-v0_9_9_tokens.sh`)
- confirm the supported token path changes across prompts and the unavailable path stays explicit with `null` token fields and a reason

## License

- confirm `LICENSE` is present and intended
- confirm release notes and README language are compatible with a public MIT release

## Onboarding

- follow `docs/operator-quickstart.md` as if you were a new user
- note any missing step or hidden assumption
- verify the trace/token wording matches what the operator actually sees in the response payloads
- fix docs before publishing if the first-run path feels ambiguous

## Final Public Readiness

- review tracked diffs one more time
- review any untracked files for accidental private leakage
- make sure the repo can be understood without outside private context
