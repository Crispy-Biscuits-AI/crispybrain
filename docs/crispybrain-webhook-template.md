# CrispyBrain Webhook Workflow Template

Current version: `v1.0.0-14-g59bd5dc`

Status: template/reference doc. n8n `2.16.1` notes below remain because they document the supported/tested target and a known webhook-test quirk.

Use this standard pattern for small CrispyBrain v0.4 webhook workflows in n8n 2.16.1.

## Required Node Order

1. `Webhook`
2. `Validate ...`
3. `Build ...`
4. `Respond to Webhook`

## Webhook Node Pattern

- Method: `POST`
- Path: stable slug such as `project-memory`
- `responseMode`: `responseNode`
- Use a stable filename that matches the workflow name.

Example:

```json
{
  "httpMethod": "POST",
  "path": "project-memory",
  "responseMode": "responseNode"
}
```

## Validation Node Pattern

Use a `Code` node to normalize `body` and return a validation result instead of throwing for expected user-input failures.

Example:

```javascript
const payload = ($json.body && typeof $json.body === 'object') ? $json.body : $json;
const query = typeof payload.query === 'string' ? payload.query.trim() : '';

if (query === '') {
  return [{ json: { is_valid: false, error: 'Missing or invalid query' } }];
}

return [{ json: { is_valid: true, query } }];
```

## Main Logic Node Pattern

Keep the main logic node separate from validation so future behavior can expand without rewriting the input guard.

Example:

```javascript
if ($json.is_valid !== true) {
  return [{ json: { ok: false, error: $json.error } }];
}

return [{
  json: {
    ok: true,
    message: 'Validation passed',
    query: $json.query
  }
}];
```

## Respond to Webhook Pattern

- Node type: `n8n-nodes-base.respondToWebhook`
- Recommended `typeVersion`: `1.5`
- `respondWith`: `firstIncomingItem`

This returns the JSON from the previous node as the HTTP response body.

## Stable Filename Rule

- Use stable filenames only.
- Do not create `-v2`, `-fixed`, or timestamped variants for normal repo workflows.
- Preferred pattern: `workflows/<workflow-name>.json`

## Useful Expression Examples

Current ISO timestamp:

```text
={{ $now.toISO() }}
```

Read request body if present:

```javascript
const payload = ($json.body && typeof $json.body === 'object') ? $json.body : $json;
```

## n8n 2.16.1 Webhook-Test Quirk

`/webhook-test/...` does not listen automatically in headless CLI-only flows. Start the listener first with the authenticated manual-run workaround:

```text
POST /rest/workflows/<workflow-id>/run
{"destinationNode":{"nodeName":"<Respond node name>"}}
```

After that returns `{"data":{"waitingForWebhook":true}}`, send the real test payload to:

```text
http://localhost:5678/webhook-test/<path>
```

The reusable helper for this repo lives at [`scripts/crispybrain-test-harness.sh`](../scripts/crispybrain-test-harness.sh).
