#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

command -v node >/dev/null 2>&1 || {
  printf 'FAIL: missing required command: node\n' >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || {
  printf 'FAIL: missing required command: jq\n' >&2
  exit 1
}

cd "${REPO_ROOT}"

node <<'EOF'
const fs = require('fs');
const path = require('path');
const childProcess = require('child_process');

const repoRoot = process.cwd();
const failures = [];
let passes = 0;

function logPass(message) {
  passes += 1;
  process.stdout.write(`PASS: ${message}\n`);
}

function logFail(message) {
  failures.push(message);
  process.stdout.write(`FAIL: ${message}\n`);
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function loadWorkflow(relPath) {
  return JSON.parse(fs.readFileSync(path.join(repoRoot, relPath), 'utf8'));
}

function findNode(workflow, nodeName) {
  const node = workflow.nodes.find((entry) => entry.name === nodeName);
  if (!node) {
    throw new Error(`Missing node ${nodeName} in ${workflow.name}`);
  }
  return node;
}

function executeCode(relPath, nodeName, { currentJson = {}, inputItems = null, nodeResults = {} } = {}) {
  const workflow = loadWorkflow(relPath);
  const code = findNode(workflow, nodeName).parameters.jsCode;
  const allItems = Array.isArray(inputItems) ? inputItems : [currentJson];
  const $input = {
    first: () => ({ json: allItems[0] ?? {} }),
    all: () => allItems.map((item) => ({ json: item })),
  };
  const lookup = (name) => {
    const value = nodeResults[name];
    const items = Array.isArray(value) ? value : (value === undefined ? [] : [value]);
    return {
      first: () => ({ json: items[0] ?? {} }),
      all: () => items.map((item) => ({ json: item })),
    };
  };
  const runner = new Function('$json', '$input', '$', code);
  return runner(currentJson, $input, lookup);
}

function executeSummary(payload) {
  return childProcess.execFileSync(
    'node',
    [path.join(repoRoot, 'scripts/summarize-crispybrain-run.js')],
    { input: JSON.stringify(payload), encoding: 'utf8' },
  );
}

function runTest(name, fn) {
  try {
    fn();
    logPass(name);
  } catch (error) {
    logFail(`${name}: ${error.message}`);
  }
}

runTest('valid ingest path produces traceable normalized + chunked payload', () => {
  const normalizeOutput = executeCode('workflows/ingest.json', 'Normalize Input', {
    currentJson: {
      body: {
        filepath: '/tmp/alpha-notes.md',
        content: 'Alpha roadmap\n\n' + 'This is a realistic paragraph about CrispyBrain. '.repeat(60),
        project_slug: 'alpha',
        modifiedEpoch: 1710000000,
      },
    },
  })[0].json;
  assert(normalizeOutput.request_ok === true, 'Normalize Input should accept valid ingest input');
  assert(typeof normalizeOutput.trace?.run_id === 'string', 'Normalize Input should mint run_id');
  assert(typeof normalizeOutput.content_hash === 'string', 'Normalize Input should compute content_hash');

  const chunkOutput = executeCode('workflows/ingest.json', 'Chunk Content', {
    currentJson: normalizeOutput,
  })[0].json;
  assert(chunkOutput.chunking_ok === true, 'Chunk Content should succeed for valid input');
  assert(chunkOutput.totalChunks >= 1, 'Chunk Content should emit at least one chunk');
  assert(Array.isArray(chunkOutput.trace?.stage_history), 'Chunk Content should append trace history');
  assert(chunkOutput.trace.stage_history.some((entry) => entry.stage === 'chunked'), 'Chunk trace should record chunked stage');
});

runTest('invalid ingest path rejects empty content with explicit reason', () => {
  const output = executeCode('workflows/ingest.json', 'Normalize Input', {
    currentJson: {
      body: {
        filepath: '/tmp/empty.md',
        content: '   ',
        project_slug: 'alpha',
      },
    },
  })[0].json;
  assert(output.request_ok === false, 'Normalize Input should reject empty content');
  assert(output.error?.code === 'EMPTY_CONTENT', 'Expected EMPTY_CONTENT error code');
  assert(output.trace?.status === 'rejected', 'Trace status should show rejection');
});

runTest('edge path splits large content into multiple deterministic chunks', () => {
  const normalizeOutput = executeCode('workflows/ingest.json', 'Normalize Input', {
    currentJson: {
      body: {
        filepath: '/tmp/edge.md',
        content: 'Edge content. '.repeat(400),
        project_slug: 'alpha',
      },
    },
  })[0].json;
  const chunkOutput = executeCode('workflows/ingest.json', 'Chunk Content', {
    currentJson: normalizeOutput,
  })[0].json;
  assert(chunkOutput.totalChunks > 1, 'Expected multi-chunk output for large content');
  assert(chunkOutput.chunks[0].chunkIndex === 1, 'Chunk indexes should start at 1');
  assert(chunkOutput.chunks[chunkOutput.chunks.length - 1].totalChunks === chunkOutput.totalChunks, 'Chunk metadata should preserve total chunk count');
});

runTest('duplicate and partial ingest detection reject replayed work', () => {
  const normalizeOutput = executeCode('workflows/ingest.json', 'Normalize Input', {
    currentJson: {
      body: {
        filepath: '/tmp/replay.md',
        content: 'Replay body. '.repeat(160),
        project_slug: 'alpha',
      },
    },
  })[0].json;
  const chunkOutput = executeCode('workflows/ingest.json', 'Chunk Content', {
    currentJson: normalizeOutput,
  })[0].json;
  const batchOutput = executeCode('workflows/ingest.json', 'Build Embedding Batch Request', {
    currentJson: chunkOutput,
  })[0].json;

  const duplicateOutput = executeCode('workflows/ingest.json', 'Classify Existing Ingest State', {
    inputItems: [{ existing_chunk_count: batchOutput.totalChunks, existing_run_ids: ['prior-run'] }],
    nodeResults: {
      'Build Embedding Batch Request': batchOutput,
    },
  })[0].json;
  assert(duplicateOutput.ingest_ready === false, 'Duplicate replay should not continue');
  assert(duplicateOutput.error?.code === 'DUPLICATE_INGEST', 'Expected duplicate replay error code');

  const partialOutput = executeCode('workflows/ingest.json', 'Classify Existing Ingest State', {
    inputItems: [{ existing_chunk_count: Math.max(batchOutput.totalChunks - 1, 1), existing_run_ids: ['partial-run'] }],
    nodeResults: {
      'Build Embedding Batch Request': batchOutput,
    },
  })[0].json;
  assert(partialOutput.ingest_ready === false, 'Partial ingest should not continue');
  assert(partialOutput.error?.code === 'PARTIAL_INGEST_DETECTED', 'Expected partial ingest error code');
});

runTest('assistant tracing propagates through empty retrieval responses', () => {
  const normalizeOutput = executeCode('workflows/assistant.json', 'Normalize Assistant Request', {
    currentJson: {
      body: {
        message: 'What is CrispyBrain?',
        project_slug: 'alpha',
        correlation_id: 'corr-assistant-123',
      },
    },
  })[0].json;
  assert(normalizeOutput.request_ok === true, 'Assistant normalize should accept valid input');
  assert(normalizeOutput.trace?.correlation_id === 'corr-assistant-123', 'Assistant should preserve incoming correlation_id');

  const emptyOutput = executeCode('workflows/assistant.json', 'Build Empty Retrieval Response', {
    currentJson: {
      query: normalizeOutput.query,
      session_id: normalizeOutput.session_id,
      project_slug: normalizeOutput.project_slug,
      top_k: normalizeOutput.top_k,
      retrieval_strategy: normalizeOutput.retrieval_strategy,
      project_match_count: 0,
      general_match_count: 0,
      strongest_similarity: null,
      similarity_threshold: 0.72,
      session_turn_count_before: 0,
      trace: normalizeOutput.trace,
    },
  })[0].json;

  assert(emptyOutput.ok === true, 'Empty retrieval response should still be a successful answer path');
  assert(emptyOutput.trace?.correlation_id === 'corr-assistant-123', 'Empty retrieval response should preserve correlation_id');
  assert(emptyOutput.trace?.stage === 'retrieval_empty', 'Empty retrieval trace should identify retrieval_empty stage');

  const summary = executeSummary(emptyOutput);
  assert(summary.includes('correlation_id: corr-assistant-123'), 'Summary helper should print correlation_id');
  assert(summary.includes('stage: retrieval_empty'), 'Summary helper should print final stage');
});

runTest('search workflow hardening exposes invalid project slugs at the boundary', () => {
  const output = executeCode('workflows/search-by-embedding.json', 'Normalize Input', {
    currentJson: {
      body: {
        query: 'find alpha notes',
        project_slug: 'Alpha Space',
      },
    },
  })[0].json;
  assert(output.request_ok === false, 'Search normalize should reject invalid slug formatting');
  assert(output.error?.code === 'INVALID_PROJECT_SLUG', 'Expected INVALID_PROJECT_SLUG from search normalize');
});

runTest('safe retry settings exist on transient external calls', () => {
  const assistant = loadWorkflow('workflows/assistant.json');
  const ingest = loadWorkflow('workflows/ingest.json');
  const search = loadWorkflow('workflows/search-by-embedding.json');

  assert(findNode(assistant, 'Generate Query Embedding').retryOnFail === true, 'Assistant embedding should retry safely');
  assert(findNode(assistant, 'Generate Assistant Answer').retryOnFail === true, 'Assistant answer generation should retry safely');
  assert(findNode(ingest, 'Embed Chunks').retryOnFail === true, 'Ingest embeddings should retry safely');
  assert(findNode(search, 'Generate Query Embedding').retryOnFail === true, 'Search embeddings should retry safely');
});

runTest('v0.5 docs exist', () => {
  assert(fs.existsSync(path.join(repoRoot, 'docs/crispybrain-v0_5.md')), 'Missing docs/crispybrain-v0_5.md');
  assert(fs.existsSync(path.join(repoRoot, 'docs/observability.md')), 'Missing docs/observability.md');
});

if (failures.length > 0) {
  process.stdout.write(`\nFAIL: ${failures.length} v0.5 checks failed\n`);
  for (const failure of failures) {
    process.stdout.write(` - ${failure}\n`);
  }
  process.exit(1);
}

process.stdout.write(`\nPASS: ${passes} v0.5 checks passed\n`);
EOF
