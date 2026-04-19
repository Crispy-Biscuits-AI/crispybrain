#!/usr/bin/env node

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const SAFE_MIN_CYCLE_COUNT = 3;
const SAFE_MAX_CYCLE_COUNT = 12;
const RULE_DESCRIPTION = {
  minContentLength: 20,
  replacementCharacter: '\uFFFD',
  minAlphaCount: 12,
  minSafeCharRatio: 0.7,
  safeCharPattern: "[A-Za-z0-9\\s.,:;!?()'\"_\\/-]",
};

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

function detectContainer(preferred, fallback) {
  const override = process.env.CRISPYBRAIN_HARNESS_DB_CONTAINER || process.env.CRISPYBRAIN_DB_CONTAINER;
  if (override) {
    return override;
  }
  const names = execFileSync('docker', ['ps', '--format', '{{.Names}}'], { encoding: 'utf8' })
    .trim()
    .split('\n')
    .filter(Boolean);
  if (names.includes(preferred)) {
    return preferred;
  }
  return fallback;
}

function parseArgs(argv) {
  const options = {
    mode: 'summary',
    format: 'table',
    limit: null,
    outputPath: null,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--mode') {
      options.mode = argv[index + 1];
      index += 1;
    } else if (arg === '--json') {
      options.format = 'json';
    } else if (arg === '--format') {
      options.format = argv[index + 1];
      index += 1;
    } else if (arg === '--limit') {
      const value = argv[index + 1];
      index += 1;
      if (value !== undefined && value !== 'all') {
        options.limit = Number.parseInt(value, 10);
      }
    } else if (arg === '--out') {
      options.outputPath = argv[index + 1];
      index += 1;
    } else if (arg === '--help' || arg === '-h') {
      options.help = true;
    } else {
      fail(`Unknown argument: ${arg}`);
    }
  }

  if (options.limit !== null && (!Number.isInteger(options.limit) || options.limit < 1)) {
    fail('--limit must be a positive integer or "all"');
  }
  if (!['summary', 'suspect', 'clean', 'export-suspect'].includes(options.mode)) {
    fail(`Unsupported mode: ${options.mode}`);
  }
  if (!['table', 'json'].includes(options.format)) {
    fail(`Unsupported format: ${options.format}`);
  }

  return options;
}

function usage() {
  return [
    'Usage:',
    '  node scripts/inspect-crispybrain-memory.js --mode summary',
    '  node scripts/inspect-crispybrain-memory.js --mode suspect --limit 10',
    '  node scripts/inspect-crispybrain-memory.js --mode clean --json',
    '  node scripts/inspect-crispybrain-memory.js --mode export-suspect --out seed-data/suspect-memories.json',
    '',
    'Modes:',
    '  summary         Show counts and reason breakdown',
    '  suspect         List rows that fail the v0.5.1 suspect-row rule',
    '  clean           List rows that pass the v0.5.1 suspect-row rule',
    '  export-suspect  Emit suspect rows as JSON to stdout or --out',
  ].join('\n');
}

function queryRows(containerName) {
  const sql = [
    'SELECT COALESCE(json_agg(row_to_json(t))::text, \'[]\')',
    'FROM (',
    '  SELECT',
    '    id,',
    '    created_at,',
    '    title,',
    '    content,',
    '    metadata_json->>\'filepath\' AS filepath,',
    '    metadata_json->>\'project_slug\' AS project_slug,',
    '    metadata_json->>\'run_id\' AS run_id,',
    '    metadata_json->>\'correlation_id\' AS correlation_id',
    '  FROM memories',
    '  ORDER BY id ASC',
    ') t;',
  ].join(' ');

  const raw = execFileSync(
    'docker',
    ['exec', containerName, 'psql', '-U', 'n8n', '-d', 'n8n', '-t', '-A', '-c', sql],
    { encoding: 'utf8' },
  ).trim();

  return JSON.parse(raw || '[]');
}

function classifyContent(content) {
  const value = typeof content === 'string' ? content.trim() : '';
  const reasons = [];

  if (value.length < RULE_DESCRIPTION.minContentLength) {
    reasons.push('content_too_short');
  }
  if (value.includes(RULE_DESCRIPTION.replacementCharacter)) {
    reasons.push('contains_replacement_character');
  }

  const alphaCount = (value.match(/[A-Za-z]/g) ?? []).length;
  if (alphaCount < RULE_DESCRIPTION.minAlphaCount) {
    reasons.push('alpha_count_below_min');
  }

  const safeCount = (value.match(/[A-Za-z0-9\s.,:;!?()'"_\/-]/g) ?? []).length;
  const safeCharRatio = value.length > 0 ? safeCount / value.length : 0;
  if (safeCharRatio < RULE_DESCRIPTION.minSafeCharRatio) {
    reasons.push('safe_char_ratio_below_threshold');
  }

  return {
    isSuspect: reasons.length > 0,
    reasons,
    contentLength: value.length,
    alphaCount,
    safeCharRatio: Number(safeCharRatio.toFixed(3)),
  };
}

function preview(content) {
  const text = typeof content === 'string' ? content.replace(/\s+/g, ' ').trim() : '';
  if (text.length <= 140) {
    return text;
  }
  return `${text.slice(0, 137)}...`;
}

function classifyRows(rows) {
  return rows.map((row) => {
    const classification = classifyContent(row.content);
    const filepath = row.filepath || null;
    const filename = filepath ? path.basename(filepath) : null;
    return {
      id: Number(row.id),
      project_slug: row.project_slug || null,
      title: row.title || null,
      filename,
      filepath,
      content_preview: preview(row.content),
      reason_flagged: classification.reasons,
      content_length: classification.contentLength,
      created_at: row.created_at || null,
      run_id: row.run_id || null,
      correlation_id: row.correlation_id || null,
      alpha_count: classification.alphaCount,
      safe_char_ratio: classification.safeCharRatio,
      classification: classification.isSuspect ? 'suspect' : 'clean',
    };
  });
}

function buildSummary(rows) {
  const summary = {
    total_rows: rows.length,
    suspect_rows: 0,
    clean_rows: 0,
    suspect_ids: [],
    reason_counts: {},
    projects: {},
    rule: {
      min_content_length: RULE_DESCRIPTION.minContentLength,
      replacement_character: RULE_DESCRIPTION.replacementCharacter,
      min_alpha_count: RULE_DESCRIPTION.minAlphaCount,
      min_safe_char_ratio: RULE_DESCRIPTION.minSafeCharRatio,
    },
  };

  for (const row of rows) {
    if (row.classification === 'suspect') {
      summary.suspect_rows += 1;
      summary.suspect_ids.push(row.id);
      for (const reason of row.reason_flagged) {
        summary.reason_counts[reason] = (summary.reason_counts[reason] ?? 0) + 1;
      }
    } else {
      summary.clean_rows += 1;
    }
    const projectKey = row.project_slug || 'unscoped';
    summary.projects[projectKey] = summary.projects[projectKey] ?? { total: 0, suspect: 0, clean: 0 };
    summary.projects[projectKey].total += 1;
    summary.projects[projectKey][row.classification] += 1;
  }

  return summary;
}

function toJson(value) {
  return JSON.stringify(value, null, 2);
}

function renderSummaryTable(summary, containerName) {
  const lines = [
    'CrispyBrain Memory Inspection Summary',
    `DB container: ${containerName}`,
    `Total rows: ${summary.total_rows}`,
    `Suspect rows: ${summary.suspect_rows}`,
    `Clean rows: ${summary.clean_rows}`,
    `Suspect IDs: ${summary.suspect_ids.length > 0 ? summary.suspect_ids.join(', ') : '(none)'}`,
    '',
    'Rule:',
    `  min_content_length: ${summary.rule.min_content_length}`,
    `  replacement_character: ${summary.rule.replacement_character}`,
    `  min_alpha_count: ${summary.rule.min_alpha_count}`,
    `  min_safe_char_ratio: ${summary.rule.min_safe_char_ratio}`,
    '',
    'Reason counts:',
  ];

  const reasonEntries = Object.entries(summary.reason_counts);
  if (reasonEntries.length === 0) {
    lines.push('  (none)');
  } else {
    for (const [reason, count] of reasonEntries.sort(([left], [right]) => left.localeCompare(right))) {
      lines.push(`  ${reason}: ${count}`);
    }
  }

  lines.push('', 'Project counts:');
  for (const [project, counts] of Object.entries(summary.projects).sort(([left], [right]) => left.localeCompare(right))) {
    lines.push(`  ${project}: total=${counts.total}, suspect=${counts.suspect}, clean=${counts.clean}`);
  }

  return lines.join('\n');
}

function renderRowsTable(rows, heading) {
  const lines = [heading];
  if (rows.length === 0) {
    lines.push('(none)');
    return lines.join('\n');
  }

  for (const row of rows) {
    lines.push(
      [
        `[${row.id}] ${row.title || row.filename || '(untitled)'}`,
        `  project_slug: ${row.project_slug || '(none)'}`,
        `  filename: ${row.filename || '(none)'}`,
        `  filepath: ${row.filepath || '(none)'}`,
        `  preview: ${row.content_preview || '(empty)'}`,
        `  reason_flagged: ${row.reason_flagged.length > 0 ? row.reason_flagged.join(', ') : '(clean)'}`,
        `  content_length: ${row.content_length}`,
        `  created_at: ${row.created_at || '(unknown)'}`,
        `  run_id: ${row.run_id || '(none)'}`,
        `  correlation_id: ${row.correlation_id || '(none)'}`,
      ].join('\n'),
    );
  }

  return lines.join('\n\n');
}

function maybeLimit(rows, limit) {
  if (limit === null) {
    return rows;
  }
  return rows.slice(0, limit);
}

function writeOutput(output, outputPath) {
  if (!outputPath) {
    process.stdout.write(`${output}\n`);
    return;
  }
  fs.writeFileSync(outputPath, `${output}\n`, 'utf8');
  process.stdout.write(`Wrote ${outputPath}\n`);
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }

  const containerName = detectContainer('crispy-ai-lab-postgres-1', 'ai-postgres');
  const rows = classifyRows(queryRows(containerName));
  const summary = buildSummary(rows);
  const suspectRows = rows.filter((row) => row.classification === 'suspect');
  const cleanRows = rows.filter((row) => row.classification === 'clean');

  let payload;
  let text;

  if (options.mode === 'summary') {
    payload = summary;
    text = renderSummaryTable(summary, containerName);
  } else if (options.mode === 'suspect') {
    payload = maybeLimit(suspectRows, options.limit);
    text = renderRowsTable(payload, 'Suspect memory rows');
  } else if (options.mode === 'clean') {
    payload = maybeLimit(cleanRows, options.limit);
    text = renderRowsTable(payload, 'Clean memory rows');
  } else if (options.mode === 'export-suspect') {
    payload = suspectRows;
    text = toJson(payload);
  } else {
    fail(`Unhandled mode: ${options.mode}`);
  }

  if (options.mode === 'export-suspect') {
    writeOutput(toJson(payload), options.outputPath);
    return;
  }

  const output = options.format === 'json' ? toJson(payload) : text;
  writeOutput(output, options.outputPath);
}

main();
