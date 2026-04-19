# Open Source Readiness Audit

## Ready Now

- The repo contains real public-facing product assets: workflow exports, SQL, helper scripts, docs, and artwork.
- The product story can be stated clearly as a self-hosted `n8n + Postgres + Ollama` memory assistant.
- No obvious secrets are tracked in the inspected files.
- `.DS_Store` is already ignored in `.gitignore`.
- The runtime-sensitive naming debt is contained enough to document rather than block release.

## Fixed In This Pass

- Added a real MIT `LICENSE`.
- Rewrote `README.md` to describe CrispyBrain as the product rather than an internal fork narrative.
- Replaced public-facing absolute local file links with repo-relative links in tracked docs.
- Added onboarding, scope, contribution, and release docs needed for a public audience.
- Added `.env.example` and updated `.gitignore` so it can be committed safely.
- Removed shellcheck source comments that hardcoded a local machine path in tracked scripts.
- Removed obvious root-level `.DS_Store` clutter if present.

## Still Needs Manual Review

- `docs/crispybrain-v0.4-chat.html` is already modified in the working tree and should get a quick visual/public copy review before release.
- `docs/assets/` is untracked and should be reviewed to decide whether it belongs in the public repo.
- `scripts/verify-crispybrain-health.sh` is untracked and should be reviewed before publishing.
- `workflows/crispybrain-build-context.json` is untracked and may represent newer workflow logic than the tracked `workflows/build-context.json`.
- The helper scripts assume a local runtime shape and should be tested once in a clean outsider-style setup before tagging a release.

## Acceptable Known Limitations

- The checked-in SQL only creates the `openbrain_chat_turns` table; the workflows also assume existing `memories` and `projects` tables.
- The workflows call Ollama at `http://host.docker.internal:11434`, so host access must be available from n8n.
- The exported workflows expect an n8n credential named `Postgres account`.
- Some runtime-sensitive legacy names remain for compatibility and are documented in [legacy-naming-debt.md](legacy-naming-debt.md).
- This repo is a technical early release, not yet a polished turnkey installer.
