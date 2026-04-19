# Ingesting Text into CrispyBrain

CrispyBrain can store plain text as memory and use it later when you ask a question.
In the current local setup, the simplest path is to drop a `.txt` file into the lab inbox and then query that project in the demo UI.

This guide assumes you are using the default local lab setup from `crispy-ai-lab` and that the ingest/watch workflows are already active in n8n.

## The Simplest Path

Step 1 — Create a text file

- Use a plain `.txt` file.
- Keep it small and specific for the first test.

Step 2 — Place it in the inbox folder

- Default folder structure: `crispybrain/inbox/<project-slug>/`
- Default local lab example: `../crispy-ai-lab/crispybrain/inbox/alpha/`
- Example file path: `../crispy-ai-lab/crispybrain/inbox/alpha/my-notes.txt`

If the `alpha` folder does not exist yet, create it first.

Step 3 — Wait briefly

- In a working local lab setup, give it about 60 seconds.
- This gives the current ingest/watch path time to pick up the file and store memory rows.

Step 4 — Ask a question in the UI

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

- the file is picked up by the current ingest path
- the text is split into chunks
- the chunks are stored in Postgres as memory
- later, the assistant retrieves the relevant chunks when you ask a question

## How to Know It Worked

- If the answer uses the ideas from your file, it worked.
- If you want a deeper check, look at recent n8n executions for the ingest path.

## Current Limitations

- Plain text `.txt` files are the safest path today.
- PDFs and other document formats are not the simple default path here.
- This depends on the ingest/watch workflows being active in your local n8n setup.
- The default demo setup is strongest with project slug `alpha` unless you have configured another project path.
