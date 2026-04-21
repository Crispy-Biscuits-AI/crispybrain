#!/usr/bin/env node

'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const repoRoot = path.resolve(__dirname, '..');
const assistantWorkflowPath = path.join(repoRoot, 'workflows', 'assistant.json');
const demoWorkflowPath = path.join(repoRoot, 'workflows', 'crispybrain-demo.json');

function readWorkflow(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function findNode(workflow, nodeId) {
  const node = workflow.nodes.find((entry) => entry.id === nodeId);
  if (!node) {
    throw new Error(`Missing workflow node: ${nodeId}`);
  }
  return node;
}

function runCodeNode(workflowPath, nodeId, itemJson, namedInputs) {
  const workflow = readWorkflow(workflowPath);
  const node = findNode(workflow, nodeId);
  const wrappedSource = `(function () {\n${node.parameters.jsCode}\n})()`;
  const script = new vm.Script(wrappedSource, {
    filename: `${path.basename(workflowPath)}:${nodeId}`,
  });

  const sandbox = {
    $json: itemJson,
    $: (name) => ({
      first: () => ({ json: namedInputs[name] ?? null }),
    }),
    console: { log() {} },
    JSON,
    Number,
    String,
    Boolean,
    Array,
    Date,
    Math,
    Object,
    RegExp,
    Set,
    Map,
    parseInt,
    parseFloat,
    isNaN,
    Infinity,
    NaN,
  };

  const result = script.runInNewContext(sandbox, { timeout: 1000 });
  if (!Array.isArray(result) || !result[0] || typeof result[0].json !== 'object') {
    throw new Error(`Unexpected result shape from ${nodeId}`);
  }
  return result[0].json;
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function assertEqual(actual, expected, message) {
  assert(actual === expected, `${message}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}

const sourceRecord = {
  id: 101,
  title: 'alpha-plan.txt :: chunk 01',
  filename: 'alpha-plan.txt',
  chunk_index: 1,
  similarity: 0.81,
  lexical_overlap: 4,
  strong_token_hits: 0,
  review_status: 'reviewed',
};

const assistantBase = {
  query: 'How am I planning to build CrispyBrain?',
  session_id: 'token-contract-session',
  project_slug: 'alpha',
  top_k: 5,
  retrieval_strategy: 'project-first-fallback-general',
  project_match_count: 1,
  general_match_count: 0,
  lexical_project_match_count: 1,
  lexical_general_match_count: 0,
  lexical_all_match_count: 1,
  usable_memory_count: 1,
  suspect_memory_count: 0,
  strong_memory_count: 1,
  strongest_similarity: 0.81,
  similarity_threshold: 0.72,
  trust: {
    overall_band: 'medium',
    evidence_strength: 'moderate',
    reviewed_source_count: 1,
  },
  grounding: {
    status: 'grounded',
    weak_grounding: false,
    note: 'Visible repo notes support this answer.',
    supporting_source_count: 1,
    reviewed_source_count: 1,
    strongest_similarity: 0.81,
    similarity_threshold: 0.72,
  },
  sources: [sourceRecord],
  selected_sources: [sourceRecord],
  retrieved_candidates: [sourceRecord],
  answer_mode: 'direct',
  conflict_flag: false,
  conflict_severity: null,
  conflict_details: [],
  claim_support_counts: [],
  claim_support_counts_raw: [],
  claim_support_counts_deduped: [],
  claim_weighted_support: [],
  claim_independent_support: [],
  claim_independence_adjusted_support: [],
  dominant_claim_status: null,
  dominant_claim_basis: null,
  claim_confidence: null,
  conflict_summary_hint: null,
  most_supported_claim: null,
  most_recent_claim: null,
  source_quality_breakdown: [],
  source_independence_breakdown: [],
  evidence_clusters: [],
  entity_focus: null,
  filtered_candidate_count: 1,
  context_preview: 'Memory 1: alpha-plan.txt',
  session_turn_count_before: 0,
  trace: {
    run_id: 'run-contract-1',
    correlation_id: 'corr-contract-1',
    ranking_mode: 'semantic',
    stage_history: [],
    workflow_chain: ['assistant'],
  },
};

const assistantSuccess = runCodeNode(
  assistantWorkflowPath,
  'code-build-assistant-response',
  {
    statusCode: 200,
    body: {
      response: 'CrispyBrain exposes grounded answers from visible project notes.',
      prompt_eval_count: 12,
      eval_count: 7,
    },
  },
  {
    'Assemble Retrieval Context': assistantBase,
  },
);

assertEqual(assistantSuccess.usage.provider, 'ollama', 'assistant success usage provider');
assertEqual(assistantSuccess.usage.available, true, 'assistant success usage availability');
assertEqual(assistantSuccess.usage.input_tokens, 12, 'assistant success input tokens');
assertEqual(assistantSuccess.usage.output_tokens, 7, 'assistant success output tokens');
assertEqual(assistantSuccess.usage.total_tokens, 19, 'assistant success total tokens');
assertEqual(assistantSuccess.trace.input_tokens, 12, 'assistant trace input tokens');
assertEqual(assistantSuccess.trace.output_tokens, 7, 'assistant trace output tokens');
assertEqual(assistantSuccess.trace.total_tokens, 19, 'assistant trace total tokens');

const assistantEmpty = runCodeNode(
  assistantWorkflowPath,
  'code-build-empty-retrieval-response',
  {
    query: 'What does missing token CB-TOKEN-USAGE-UNAVAILABLE refer to?',
    session_id: 'token-contract-empty',
    project_slug: 'alpha',
    top_k: 5,
    retrieval_strategy: 'project-first-fallback-general',
    project_match_count: 0,
    general_match_count: 0,
    lexical_project_match_count: 0,
    lexical_general_match_count: 0,
    lexical_all_match_count: 0,
    usable_memory_count: 0,
    suspect_memory_count: 0,
    strongest_similarity: null,
    similarity_threshold: 0.72,
    retrieved_candidates: [],
    entity_focus: null,
    filtered_candidate_count: 0,
    session_turn_count_before: 0,
    trace: {
      run_id: 'run-contract-empty',
      correlation_id: 'corr-contract-empty',
      ranking_mode: 'semantic',
      stage_history: [],
    },
  },
  {},
);

assertEqual(assistantEmpty.usage.available, false, 'assistant empty usage availability');
assertEqual(assistantEmpty.usage.reason, 'answer_not_generated', 'assistant empty usage reason');
assertEqual(assistantEmpty.usage.input_tokens, null, 'assistant empty input tokens');
assertEqual(assistantEmpty.trace.usage_reason, 'answer_not_generated', 'assistant empty trace usage reason');

const demoRequest = {
  question: 'What can CrispyBrain do today?',
  project_slug: 'alpha',
  session_id: 'demo-contract-session',
  defaulted_project_slug: false,
  trace: {
    run_id: 'run-demo-contract',
    correlation_id: 'corr-demo-contract',
    workflow_chain: ['crispybrain-demo'],
    stage_history: [],
  },
};

const demoSuccess = runCodeNode(
  demoWorkflowPath,
  'code-build-demo-response',
  {
    statusCode: 200,
    body: {
      ok: true,
      answer: 'CrispyBrain shows grounded answers, sources, and trace details.',
      project_slug: 'alpha',
      usage: assistantSuccess.usage,
      retrieval: {
        memory_count: 1,
        empty: false,
        strongest_similarity: 0.81,
        similarity_threshold: 0.72,
      },
      trust: {
        reviewed_source_count: 1,
        evidence_strength: 'moderate',
        overall_band: 'medium',
      },
      grounding: assistantBase.grounding,
      sources: [sourceRecord],
      selected_sources: [sourceRecord],
      retrieved_candidates: [sourceRecord],
      answer_mode: 'direct',
      conflict_flag: false,
      filtered_candidate_count: 1,
      trace: assistantSuccess.trace,
    },
  },
  {
    'Normalize Demo Request': demoRequest,
  },
);

assertEqual(demoSuccess.usage.total_tokens, 19, 'demo success total tokens');
assertEqual(demoSuccess.debug.input_tokens, 12, 'demo debug input tokens');
assertEqual(demoSuccess.trace.input_tokens, 12, 'demo trace input tokens');

const demoMissingUsage = runCodeNode(
  demoWorkflowPath,
  'code-build-demo-response',
  {
    statusCode: 200,
    body: {
      ok: true,
      answer: 'CrispyBrain shows grounded answers, sources, and trace details.',
      project_slug: 'alpha',
      retrieval: {
        memory_count: 1,
        empty: false,
        strongest_similarity: 0.81,
        similarity_threshold: 0.72,
      },
      trust: {
        reviewed_source_count: 1,
        evidence_strength: 'moderate',
        overall_band: 'medium',
      },
      grounding: assistantBase.grounding,
      sources: [sourceRecord],
      selected_sources: [sourceRecord],
      retrieved_candidates: [sourceRecord],
      answer_mode: 'direct',
      conflict_flag: false,
      filtered_candidate_count: 1,
      trace: assistantSuccess.trace,
    },
  },
  {
    'Normalize Demo Request': demoRequest,
  },
);

assertEqual(demoMissingUsage.usage.available, false, 'demo missing usage availability');
assertEqual(demoMissingUsage.usage.reason, 'upstream_usage_missing', 'demo missing usage reason');
assertEqual(demoMissingUsage.debug.usage_reason, 'upstream_usage_missing', 'demo missing usage debug reason');

process.stdout.write('PASS: token contract workflow checks passed\n');
