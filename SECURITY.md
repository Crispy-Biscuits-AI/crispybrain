# Security

CrispyBrain is currently an experimental local-first demo and workflow repo, not a production-hardened hosted service.

## Please Do Not Commit

- `.env` files
- API keys or tokens
- private memory content
- customer data
- machine-specific local paths unless they are intentionally documented and generalized

## Reporting

If you find a security issue or accidentally discover a secret in tracked files, do not open a public issue with the raw secret or exploit details.

Share a redacted report through a private maintainer channel first if one is available. If you only have GitHub, open a minimal report without the sensitive payload.
