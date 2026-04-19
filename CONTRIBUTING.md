# Contributing

Thanks for helping improve CrispyBrain.

## Before You Open A Change

- keep the public story truthful
- prefer smaller, well-scoped changes
- update docs when behavior or setup assumptions change
- avoid adding complexity unless it clearly earns its place

## Workflow Changes

If you edit workflows in n8n:

- export the updated workflow JSON back into `workflows/`
- keep stable filenames for the current product path
- document any new credential, model, or setup dependency
- note runtime-sensitive changes in `docs/legacy-naming-debt.md` if relevant

## Documentation Expectations

- write for an outside operator, not just a current maintainer
- avoid local absolute paths and private environment assumptions
- call out limitations plainly instead of hiding them

## Pull Requests

- explain what changed and why
- mention any workflow exports that were refreshed
- mention any setup or release-doc updates that should be reviewed alongside code

For release hygiene, see [docs/release-checklist.md](docs/release-checklist.md).
