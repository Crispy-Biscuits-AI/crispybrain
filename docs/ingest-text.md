# Ingesting Text into CrispyBrain

CrispyBrain can store plain text as memory and use it later when you ask a question.
In the current local setup, the canonical path is to drop a `.txt` file into the CrispyBrain repo inbox and then query that project in the demo UI.

The canonical watcher workflow is `auto-ingest-watch`, and its downstream handoff is the canonical ingest webhook `POST /webhook/ingest`.

Current verified blocker in this local lab runtime:

- the active watcher is running in n8n
- it watches `/home/node/.n8n-files/crispybrain/inbox` inside the container
- a real file drop into `/Users/elric/repos/crispybrain/inbox/<project-slug>/` did not appear at that watched container path
- as a result, the repo inbox is still passive in the current runtime until the container mount is updated

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

Step 3 — Verify the runtime mount before expecting file-drop ingest

- In a truly live file-drop setup, the same file must also become visible to n8n under `/home/node/.n8n-files/crispybrain/inbox/<project-slug>/`.
- If it does not appear there, the watcher cannot see the repo inbox yet.

Step 4 — Wait briefly

- In a working local lab setup, give it about 60 seconds.
- This gives `auto-ingest-watch` time to detect the file and hand it to `/webhook/ingest`.

Step 5 — Ask a question in the UI

- Open `http://localhost:8787`
- Use project slug `alpha`
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

## How to Know It Worked

- If the answer uses the ideas from your file, it worked.
- If you want a deeper check, look at recent n8n executions for both `auto-ingest-watch` and `ingest`.
- If no watcher execution appears after a real repo-path file drop, the runtime mount is still the blocker.

## Current Limitations

- Plain text `.txt` files are the safest path today.
- PDFs and other document formats are not the simple default path here.
- This depends on the ingest/watch workflows being active in your local n8n setup.
- In the current verified lab runtime, the active watcher sees `/home/node/.n8n-files/crispybrain/inbox`, not the host repo path directly.
- Until the n8n bind mount is updated to expose `/Users/elric/repos/crispybrain/inbox`, a real repo-path file drop will not trigger ingest.
- The default demo setup is strongest with project slug `alpha` unless you have configured another project path.
