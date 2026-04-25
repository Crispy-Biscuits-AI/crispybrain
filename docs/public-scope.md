# Public Scope

Current version: `v1.0.0-14-g59bd5dc`

## What This Repo Is

This repository is the public home of CrispyBrain: a self-hosted project memory assistant built around n8n workflows, Postgres, and Ollama.

## Public Core

The public core of CrispyBrain in this repo is:

- exported workflow JSON in `workflows/`
- the checked-in SQL migration in `sql/`
- operator and setup documentation in `docs/`
- helper scripts in `scripts/` for maintainers running a compatible local environment
- the current local demo in `demo/`
- the historical static chat UI in `docs/crispybrain-v0.4-chat.html`

## Optional

These things are useful but not required to understand the product:

- local helper scripts that automate import or testing in a specific Docker-based setup
- historical or experimental workflow exports kept for reference
- the static chat UI, which is helpful for demos but not the only way to use the assistant webhook

## Not Included

This public repo does not try to include:

- CMS implementation material
- private operations playbooks
- client-specific integrations
- customer data or customer-derived examples
- a complete hosted platform or SaaS control plane

## Relationship To `crispy-ai-lab`

`crispy-ai-lab` is a separate optional reference environment. It may be useful for development or local testing, but it is not the public product identity of this repo and it is not required to adopt CrispyBrain.
