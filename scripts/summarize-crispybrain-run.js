#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

function readInput() {
  const fileArg = process.argv[2];
  if (fileArg) {
    return fs.readFileSync(path.resolve(fileArg), 'utf8');
  }
  return fs.readFileSync(0, 'utf8');
}

function parsePayload(raw) {
  const parsed = JSON.parse(raw);
  if (Array.isArray(parsed)) {
    return parsed[0] ?? {};
  }
  return parsed ?? {};
}

function pickTrace(payload) {
  if (payload && typeof payload === 'object' && payload.trace && typeof payload.trace === 'object') {
    return payload.trace;
  }
  if (payload?.context_bundle?.trace && typeof payload.context_bundle.trace === 'object') {
    return payload.context_bundle.trace;
  }
  return null;
}

function line(label, value) {
  if (value === undefined || value === null || value === '') {
    return;
  }
  process.stdout.write(`${label}: ${value}\n`);
}

try {
  const payload = parsePayload(readInput());
  const trace = pickTrace(payload);

  if (!trace) {
    process.stderr.write('No trace object found in payload.\n');
    process.exit(1);
  }

  line('workflow', trace.workflow_name);
  line('run_id', trace.run_id);
  line('correlation_id', trace.correlation_id);
  line('status', trace.status);
  line('stage', trace.stage);
  line('project_slug', trace.project_slug ?? payload.project_slug);
  line('source_type', trace.source_type);
  line('filename', trace.filename ?? payload.filename);
  line('filepath', trace.filepath ?? payload.filepath);
  line('timestamp', trace.timestamp);

  if (payload.error?.code || trace.error_code) {
    line('error_code', payload.error?.code ?? trace.error_code);
    line('error_message', payload.error?.message ?? trace.error_message);
  }

  if (Array.isArray(trace.stage_history) && trace.stage_history.length > 0) {
    process.stdout.write('stage_history:\n');
    for (const entry of trace.stage_history) {
      const timestamp = entry.timestamp ?? 'unknown-time';
      const code = entry.error_code ? ` (${entry.error_code})` : '';
      process.stdout.write(`- ${timestamp} ${entry.stage}:${entry.status}${code}\n`);
    }
  }
} catch (error) {
  process.stderr.write(`Failed to summarize run payload: ${error.message}\n`);
  process.exit(1);
}
