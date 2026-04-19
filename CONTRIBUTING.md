# Contributing

Thanks for helping with CrispyBrain.

## Before You Change Anything

Start with:

1. [README.md](README.md)
2. [docs/demo-local.md](docs/demo-local.md)
3. [docs/operator-quickstart.md](docs/operator-quickstart.md)
4. [docs/legacy-naming-debt.md](docs/legacy-naming-debt.md)

## Contribution Principles

- keep the repo truthful to the current demo and workflow path
- prefer small, grounded improvements over speculative rewrites
- do not remove honest limitations just to make the repo sound cleaner
- do not commit secrets, private memory content, or local `.env` values
- keep public naming centered on CrispyBrain

## Workflow And Demo Changes

If you change the demo path or the workflow exports:

- update the relevant docs in the same change
- preserve the `localhost:8787 -> crispybrain-demo -> assistant` story unless you are deliberately changing it
- note any new manual steps or runtime assumptions explicitly
