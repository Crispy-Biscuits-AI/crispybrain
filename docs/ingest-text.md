# Ingesting Text into CrispyBrain

CrispyBrain can store plain text as memory and use it later when you ask a question.
In the current local setup, the canonical path is to drop a `.txt` file into the CrispyBrain repo inbox and then query that project in the demo UI.

The canonical watcher workflow is `auto-ingest-watch`, and its downstream handoff is the canonical ingest webhook `POST /webhook/ingest`.

In the current verified local lab runtime:

- the n8n container mounts `/Users/elric/repos/crispybrain/inbox` at `/home/node/.n8n-files/crispybrain/inbox`
- `auto-ingest-watch` polls that mounted inbox every 15 seconds
- new `.txt` files are handed to canonical `POST /webhook/ingest`

Retired endpoints that are no longer active:

- `/webhook/crispybrain-ingest`
- `/webhook/crispybrain-assistant`
- `crispybrain-auto-ingest-watch`

## The Simplest Path

Step 1 — Create a text file

- Use a plain `.txt` file.
- Keep it small and specific for the first test.

Step 2 — Place it in the inbox folder

- Canonical folder structure: `/Users/elric/repos/crispybrain/inbox/<project-slug>/`
- Relative repo path: `inbox/<project-slug>/`
- Example folder: `/Users/elric/repos/crispybrain/inbox/alpha/`
- Example file path: `/Users/elric/repos/crispybrain/inbox/alpha/my-notes.txt`

If the `alpha` folder does not exist yet, create it first.

Example:

```bash
mkdir -p /Users/elric/repos/crispybrain/inbox/alpha
```

For local file exports that should land at the repo inbox root, the demo server exposes a JSON import endpoint:

```bash
curl -sS -X POST http://localhost:8787/api/inbox/import \
  -H 'Content-Type: application/json' \
  --data '{"files":[{"filename":"example.md","content":"Exported note text\n","source":"agentic-ai-curator"}]}'
```

Sample response:

```json
{
  "success": true,
  "saved": [
    {
      "filename": "example.md",
      "path": "inbox/example.md",
      "bytes": 19,
      "timestamp": "2026-04-25T09:05:31.085349Z"
    }
  ],
  "rejected": [],
  "inbox_path": "inbox"
}
```

That endpoint writes accepted files under `/Users/elric/repos/crispybrain/inbox/` and creates the `inbox/` directory if it is missing.
It accepts only safe single filenames, rejects absolute paths and path traversal, and rejects duplicate filenames with `409` instead of overwriting.

For article memories exported by Agentic AI Curator, use the display project `Curated Articles`.
CrispyBrain's safe inbox slug for that display name is:

```text
curated-articles
```

The corresponding folder is:

```bash
mkdir -p /Users/elric/repos/crispybrain/inbox/curated-articles
```

Step 3 — Verify the runtime mount

- In a live file-drop setup, the same file should also be visible to n8n under `/home/node/.n8n-files/crispybrain/inbox/<project-slug>/`.
- That confirms the canonical repo inbox is the one the watcher is actually polling.

Step 4 — Wait briefly

- In the current verified lab setup, give it about 15 to 30 seconds.
- That gives `auto-ingest-watch` time to detect the file and hand it to `/webhook/ingest`.

Step 5 — Ask a question in the UI

- Open `http://localhost:8787`
- Use the relevant project. For Agentic AI Curator exports, select `Curated Articles` in the UI or use project slug `curated-articles` when calling the assistant webhook directly.
- Ask a question that matches the text you just added

## Example

Filename: `my-notes.txt`

Content:

```text
CrispyBrain is designed to store project notes as memory.
It can retrieve relevant text later and answer questions from that stored context.
The current local demo is meant to prove that retrieval path end to end.
```

Sample question:

```text
What is CrispyBrain designed to do?
```

## What Happens Behind the Scenes

- `auto-ingest-watch` detects the file system event
- the watcher posts the file content to `/webhook/ingest`
- the text is split into chunks
- the chunks are stored in Postgres as memory
- later, the assistant retrieves the relevant chunks when you ask a question

## Scoped Auto-Review

The ingest workflow does not auto-review ordinary user content.

The one narrow exception is the repo-controlled historical corpus under `openbrain-history`.
Rows are auto-marked as `reviewed` only when both of these are true:

- `project_slug = openbrain-history`
- `filepath` matches the trusted repo inbox path for that history pack, using either the host path or the mounted n8n container path

This keeps the trust layer intact for normal inbox content while making the curated OpenBrain/CrispyBrain history pack usable immediately after ingest.

## How to Know It Worked

- If the answer uses the ideas from your file, it worked.
- If you want a deeper check, look at recent n8n executions for both `auto-ingest-watch` and `ingest`.
- If the file is visible inside the container but `ingest` does not move, inspect the latest `auto-ingest-watch` execution for a downstream error.
- If multiple different filenames ingest as the same text, re-import [auto-ingest-watch.json](/Users/elric/repos/crispybrain/workflows/auto-ingest-watch.json), clear the affected rows, and re-run the watcher so each file is forwarded with its own current content.

## Current Limitations

- Plain text `.txt` files are the safest path today.
- PDFs and other document formats are not the simple default path here.
- This depends on the ingest/watch workflows being active in your local n8n setup.
- In the current verified lab runtime, the active watcher polls `/home/node/.n8n-files/crispybrain/inbox`, which is mounted from `/Users/elric/repos/crispybrain/inbox`.
- The watcher is intentionally file-drop only here; it does not add PDF parsing or other document ingestion behavior.
- The default demo setup is strongest with project slug `alpha` unless you have configured another project path.
- Agentic AI Curator article exports use the existing file-drop path and do not require a CrispyBrain workflow change.
