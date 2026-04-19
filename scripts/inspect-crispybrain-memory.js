#!/usr/bin/env node

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const RULE_DESCRIPTION = {
  minContentLength: 20,
  replacementCharacter: '\uFFFD',
  minAlphaCount: 12,
  minSafeCharRatio: 0.7,
};

const REVIEW_STATUSES = new Set(['unreviewed', 'reviewed', 'suspect', 'suppressed']);
const REPO_ROOT = path.resolve(__dirname, '..');
const DEFAULT_EXPORT_DIR = path.join(REPO_ROOT, 'seed-data', 'exports');
const DEFAULT_METRICS_DIR = path.join(REPO_ROOT, 'seed-data', 'metrics');

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

function ensureInsideRepo(targetPath) {
  const resolved = path.resolve(targetPath);
  if (!resolved.startsWith(`${REPO_ROOT}${path.sep}`) && resolved !== REPO_ROOT) {
    fail(`Refusing to write outside repo root: ${resolved}`);
  }
  return resolved;
}

function ensureDirectory(targetPath) {
  const resolved = ensureInsideRepo(targetPath);
  fs.mkdirSync(resolved, { recursive: true });
  return resolved;
}

function parseArgs(argv) {
  const options = {
    mode: 'summary',
    format: 'table',
    limit: null,
    outputPath: null,
    projectSlug: null,
    ids: [],
    reviewStatus: null,
    reviewNote: null,
    help: false,
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
    } else if (arg === '--project-slug') {
      options.projectSlug = argv[index + 1];
      index += 1;
    } else if (arg === '--ids') {
      options.ids = String(argv[index + 1] || '')
        .split(',')
        .map((value) => value.trim())
        .filter(Boolean);
      index += 1;
    } else if (arg === '--status') {
      options.reviewStatus = argv[index + 1];
      index += 1;
    } else if (arg === '--note') {
      options.reviewNote = argv[index + 1];
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
  if (!['summary', 'project-health', 'suspect', 'clean', 'export-suspect', 'snapshot-health', 'set-review-status'].includes(options.mode)) {
    fail(`Unsupported mode: ${options.mode}`);
  }
  if (!['table', 'json', 'csv'].includes(options.format)) {
    fail(`Unsupported format: ${options.format}`);
  }
  if (options.projectSlug !== null && typeof options.projectSlug !== 'string') {
    fail('--project-slug must be a string');
  }
  if (options.reviewStatus !== null && !REVIEW_STATUSES.has(options.reviewStatus)) {
    fail(`--status must be one of: ${Array.from(REVIEW_STATUSES).join(', ')}`);
  }
  if (options.mode === 'set-review-status' && options.ids.length === 0) {
    fail('--mode set-review-status requires --ids');
  }
  if (options.mode === 'set-review-status' && !options.reviewStatus) {
    fail('--mode set-review-status requires --status');
  }
  for (const id of options.ids) {
    if (!/^\d+$/.test(id)) {
      fail(`Invalid row id in --ids: ${id}`);
    }
  }

  return options;
}

function usage() {
  return [
    'Usage:',
    '  node scripts/inspect-crispybrain-memory.js --mode summary',
    '  node scripts/inspect-crispybrain-memory.js --mode project-health --project-slug alpha --json',
    '  node scripts/inspect-crispybrain-memory.js --mode suspect --limit 10',
    '  node scripts/inspect-crispybrain-memory.js --mode export-suspect --format csv --project-slug alpha',
    '  node scripts/inspect-crispybrain-memory.js --mode snapshot-health --project-slug alpha',
    '  node scripts/inspect-crispybrain-memory.js --mode set-review-status --ids 55 --status reviewed --note "operator review"',
    '',
    'Modes:',
    '  summary            Overall memory quality summary',
    '  project-health     Per-project health summary',
    '  suspect            List rows that fail the suspect-row rule or quality checks',
    '  clean              List rows that currently pass the suspect-row rule',
    '  export-suspect     Export suspect rows to JSON or CSV with timestamped filenames',
    '  snapshot-health    Write a timestamped health snapshot JSON file',
    '  set-review-status  Explicitly set metadata_json.review_status on selected rows',
  ].join('\n');
}

function sqlLiteral(value) {
  if (value === null || value === undefined) {
    return 'NULL';
  }
  return `'${String(value).replace(/'/g, "''")}'`;
}

function runPsql(containerName, sql) {
  return execFileSync(
    'docker',
    ['exec', containerName, 'psql', '-U', 'n8n', '-d', 'n8n', '-t', '-A', '-c', sql],
    { encoding: 'utf8' },
  ).trim();
}

function queryRows(containerName) {
  const sql = [
    'SELECT COALESCE(json_agg(row_to_json(t))::text, \'[]\')',
    'FROM (',
    '  SELECT',
    '    id,',
    '    created_at,',
    '    updated_at,',
    '    source,',
    '    category,',
    '    title,',
    '    content,',
    '    metadata_json',
    '  FROM memories',
    '  ORDER BY id ASC',
    ') t;',
  ].join(' ');

  const raw = runPsql(containerName, sql);
  return JSON.parse(raw || '[]');
}

function normalizeString(value) {
  return typeof value === 'string' && value.trim() !== '' ? value.trim() : null;
}

function normalizeReviewStatus(value) {
  const normalized = normalizeString(value);
  if (normalized && REVIEW_STATUSES.has(normalized)) {
    return normalized;
  }
  return 'unreviewed';
}

function normalizeTimestamp(value) {
  const normalized = normalizeString(value);
  if (!normalized) {
    return null;
  }
  const parsed = new Date(normalized);
  if (Number.isNaN(parsed.getTime())) {
    return null;
  }
  return parsed.toISOString();
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
    value,
    contentLength: value.length,
    alphaCount,
    safeCharRatio: Number(safeCharRatio.toFixed(3)),
  };
}

function preview(content) {
  const text = typeof content === 'string' ? content.replace(/\s+/g, ' ').trim() : '';
  if (text.length <= 160) {
    return text;
  }
  return `${text.slice(0, 157)}...`;
}

function buildContentFingerprint(row, normalizedContent) {
  const metadata = row.metadata_json && typeof row.metadata_json === 'object' ? row.metadata_json : {};
  const existing = normalizeString(metadata.content_hash);
  if (existing) {
    return existing;
  }
  return crypto.createHash('sha256').update(normalizedContent).digest('hex').slice(0, 12);
}

function buildDuplicateMap(rawRows) {
  const counts = new Map();
  for (const row of rawRows) {
    const metadata = row.metadata_json && typeof row.metadata_json === 'object' ? row.metadata_json : {};
    const normalizedContent = typeof row.content === 'string' ? row.content.trim() : '';
    if (!normalizedContent) {
      continue;
    }
    const fingerprint = buildContentFingerprint(row, normalizedContent);
    const projectSlug = normalizeString(metadata.project_slug) || 'unscoped';
    const key = `${projectSlug}|${fingerprint}`;
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return counts;
}

function trustBandFromRow(parts) {
  if (parts.reviewStatus === 'suppressed') {
    return 'suppressed';
  }
  if (parts.reviewStatus === 'suspect' || parts.isSuspect || parts.duplicateCandidate) {
    return 'low';
  }
  if (parts.missingCoreMetadataCount >= 2) {
    return 'low';
  }
  if (parts.reviewStatus === 'reviewed' && parts.missingCoreMetadataCount === 0) {
    return 'high';
  }
  return 'medium';
}

function classifyRows(rawRows) {
  const duplicateMap = buildDuplicateMap(rawRows);

  return rawRows.map((row) => {
    const metadata = row.metadata_json && typeof row.metadata_json === 'object' ? row.metadata_json : {};
    const contentInfo = classifyContent(row.content);
    const filepath = normalizeString(metadata.filepath);
    const filename = normalizeString(metadata.filename) || (filepath ? path.basename(filepath) : null);
    const projectSlug = normalizeString(metadata.project_slug);
    const sourceType = normalizeString(metadata.source_type) || normalizeString(row.source) || 'unknown';
    const reviewStatus = normalizeReviewStatus(metadata.review_status);
    const createdAt = normalizeTimestamp(row.created_at) || normalizeTimestamp(metadata.ingested_at);
    const reviewUpdatedAt = normalizeTimestamp(metadata.review_updated_at);
    const reviewNote = normalizeString(metadata.review_note);
    const runId = normalizeString(metadata.run_id);
    const correlationId = normalizeString(metadata.correlation_id);
    const fingerprint = buildContentFingerprint(row, contentInfo.value);
    const duplicateKey = `${projectSlug || 'unscoped'}|${fingerprint}`;
    const duplicateCandidate = (duplicateMap.get(duplicateKey) ?? 0) > 1;

    const qualityFlags = [];
    if (contentInfo.isSuspect) {
      qualityFlags.push(...contentInfo.reasons);
    }
    if (duplicateCandidate) {
      qualityFlags.push('duplicate_candidate');
    }

    let missingCoreMetadataCount = 0;
    if (sourceType === 'file_ingest') {
      if (!filepath) {
        qualityFlags.push('missing_filepath');
        missingCoreMetadataCount += 1;
      }
      if (!runId) {
        qualityFlags.push('missing_run_id');
        missingCoreMetadataCount += 1;
      }
      if (!normalizeTimestamp(metadata.ingested_at)) {
        qualityFlags.push('missing_ingested_at');
        missingCoreMetadataCount += 1;
      }
    }
    if (!normalizeString(metadata.source_type)) {
      qualityFlags.push('missing_source_type');
      missingCoreMetadataCount += 1;
    }
    if (reviewStatus === 'unreviewed') {
      qualityFlags.push('review_unreviewed');
    } else if (reviewStatus !== 'reviewed') {
      qualityFlags.push(`review_${reviewStatus}`);
    }

    const trustBand = trustBandFromRow({
      reviewStatus,
      isSuspect: contentInfo.isSuspect,
      duplicateCandidate,
      missingCoreMetadataCount,
    });

    return {
      id: Number(row.id),
      project_slug: projectSlug,
      source_type: sourceType,
      category: normalizeString(row.category),
      title: normalizeString(row.title),
      filename,
      filepath,
      content_preview: preview(row.content),
      reason_flagged: Array.from(new Set(qualityFlags)),
      content_length: contentInfo.contentLength,
      created_at: createdAt,
      updated_at: normalizeTimestamp(row.updated_at),
      ingested_at: normalizeTimestamp(metadata.ingested_at),
      review_status: reviewStatus,
      review_updated_at: reviewUpdatedAt,
      review_note: reviewNote,
      run_id: runId,
      correlation_id: correlationId,
      content_hash: fingerprint,
      duplicate_candidate: duplicateCandidate,
      alpha_count: contentInfo.alphaCount,
      safe_char_ratio: contentInfo.safeCharRatio,
      chunk_index: metadata.chunk_index ?? null,
      total_chunks: metadata.total_chunks ?? null,
      trust_band: trustBand,
      quality_band: trustBand === 'suppressed' ? 'suppressed' : trustBand,
      classification: contentInfo.isSuspect ? 'suspect' : 'clean',
    };
  });
}

function applyProjectFilter(rows, projectSlug) {
  if (!projectSlug) {
    return rows;
  }
  return rows.filter((row) => row.project_slug === projectSlug);
}

function buildHealthVerdict(summary) {
  if (summary.total_memory_rows === 0) {
    return 'needs-review';
  }
  const suspectRatio = summary.total_memory_rows > 0 ? summary.suspect_rows / summary.total_memory_rows : 0;
  const lowConfidenceRatio = summary.total_memory_rows > 0 ? summary.low_confidence_rows / summary.total_memory_rows : 0;
  const reviewedRatio = summary.total_memory_rows > 0 ? summary.review_status_counts.reviewed / summary.total_memory_rows : 0;

  if (suspectRatio >= 0.15 || summary.duplicate_candidate_rows > 0 || lowConfidenceRatio >= 0.4) {
    return 'needs-review';
  }
  if (summary.suspect_rows > 0 || reviewedRatio < 0.25 || summary.review_status_counts.unreviewed > summary.review_status_counts.reviewed) {
    return 'warning';
  }
  return 'healthy';
}

function buildProjectSummary(rows, projectSlug) {
  const summary = {
    project_slug: projectSlug || null,
    total_memory_rows: rows.length,
    source_type_counts: {},
    review_status_counts: {
      unreviewed: 0,
      reviewed: 0,
      suspect: 0,
      suppressed: 0,
    },
    suspect_rows: 0,
    low_confidence_rows: 0,
    duplicate_candidate_rows: 0,
    recent_ingest_activity: {
      supported: true,
      last_24h_rows: 0,
      last_7d_rows: 0,
      latest_ingested_at: null,
    },
    recent_review_activity: {
      supported: false,
      last_24h_rows: 0,
      last_7d_rows: 0,
      latest_review_updated_at: null,
    },
  };

  const now = Date.now();
  let reviewSignals = 0;

  for (const row of rows) {
    summary.source_type_counts[row.source_type] = (summary.source_type_counts[row.source_type] ?? 0) + 1;
    summary.review_status_counts[row.review_status] += 1;
    if (row.classification === 'suspect') {
      summary.suspect_rows += 1;
    }
    if (row.trust_band === 'low' || row.trust_band === 'suppressed') {
      summary.low_confidence_rows += 1;
    }
    if (row.duplicate_candidate) {
      summary.duplicate_candidate_rows += 1;
    }

    const ingestTimestamp = row.ingested_at || row.created_at;
    if (ingestTimestamp) {
      const ageMs = now - new Date(ingestTimestamp).getTime();
      if (ageMs <= 24 * 60 * 60 * 1000) {
        summary.recent_ingest_activity.last_24h_rows += 1;
      }
      if (ageMs <= 7 * 24 * 60 * 60 * 1000) {
        summary.recent_ingest_activity.last_7d_rows += 1;
      }
      if (!summary.recent_ingest_activity.latest_ingested_at || ingestTimestamp > summary.recent_ingest_activity.latest_ingested_at) {
        summary.recent_ingest_activity.latest_ingested_at = ingestTimestamp;
      }
    }

    if (row.review_updated_at) {
      reviewSignals += 1;
      const ageMs = now - new Date(row.review_updated_at).getTime();
      if (ageMs <= 24 * 60 * 60 * 1000) {
        summary.recent_review_activity.last_24h_rows += 1;
      }
      if (ageMs <= 7 * 24 * 60 * 60 * 1000) {
        summary.recent_review_activity.last_7d_rows += 1;
      }
      if (!summary.recent_review_activity.latest_review_updated_at || row.review_updated_at > summary.recent_review_activity.latest_review_updated_at) {
        summary.recent_review_activity.latest_review_updated_at = row.review_updated_at;
      }
    }
  }

  summary.recent_review_activity.supported = reviewSignals > 0 || rows.some((row) => row.review_status !== 'unreviewed');
  summary.health_verdict = buildHealthVerdict(summary);
  return summary;
}

function buildOverallSummary(rows) {
  const projectMap = new Map();
  for (const row of rows) {
    const key = row.project_slug || 'unscoped';
    if (!projectMap.has(key)) {
      projectMap.set(key, []);
    }
    projectMap.get(key).push(row);
  }

  const projects = Array.from(projectMap.entries())
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([projectSlug, projectRows]) => buildProjectSummary(projectRows, projectSlug === 'unscoped' ? null : projectSlug));

  return {
    generated_at: new Date().toISOString(),
    total_rows: rows.length,
    suspect_rows: rows.filter((row) => row.classification === 'suspect').length,
    clean_rows: rows.filter((row) => row.classification === 'clean').length,
    low_confidence_rows: rows.filter((row) => row.trust_band === 'low' || row.trust_band === 'suppressed').length,
    duplicate_candidate_rows: rows.filter((row) => row.duplicate_candidate).length,
    suspect_ids: rows.filter((row) => row.classification === 'suspect').map((row) => row.id),
    reason_counts: rows.reduce((acc, row) => {
      for (const reason of row.reason_flagged) {
        acc[reason] = (acc[reason] ?? 0) + 1;
      }
      return acc;
    }, {}),
    review_status_counts: rows.reduce((acc, row) => {
      acc[row.review_status] = (acc[row.review_status] ?? 0) + 1;
      return acc;
    }, {
      unreviewed: 0,
      reviewed: 0,
      suspect: 0,
      suppressed: 0,
    }),
    projects,
    rule: {
      min_content_length: RULE_DESCRIPTION.minContentLength,
      replacement_character: RULE_DESCRIPTION.replacementCharacter,
      min_alpha_count: RULE_DESCRIPTION.minAlphaCount,
      min_safe_char_ratio: RULE_DESCRIPTION.minSafeCharRatio,
    },
  };
}

function buildProjectHealthPayload(rows, projectSlug) {
  const filteredRows = applyProjectFilter(rows, projectSlug);
  const overall = buildOverallSummary(filteredRows);
  const projectMap = new Map();
  for (const row of filteredRows) {
    const key = row.project_slug || 'unscoped';
    if (!projectMap.has(key)) {
      projectMap.set(key, []);
    }
    projectMap.get(key).push(row);
  }
  return {
    generated_at: new Date().toISOString(),
    scope_project_slug: projectSlug || null,
    total_projects: projectMap.size,
    projects: Array.from(projectMap.entries())
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, projectRows]) => buildProjectSummary(projectRows, key === 'unscoped' ? null : key)),
    overall,
  };
}

function maybeLimit(rows, limit) {
  if (limit === null) {
    return rows;
  }
  return rows.slice(0, limit);
}

function renderSummaryTable(summary) {
  const lines = [
    'CrispyBrain Memory Inspection Summary',
    `Generated at: ${summary.generated_at || '(unknown)'}`,
    `Total rows: ${summary.total_rows}`,
    `Suspect rows: ${summary.suspect_rows}`,
    `Low-confidence rows: ${summary.low_confidence_rows}`,
    `Duplicate-candidate rows: ${summary.duplicate_candidate_rows}`,
    `Suspect IDs: ${summary.suspect_ids.length > 0 ? summary.suspect_ids.join(', ') : '(none)'}`,
    '',
    'Review status counts:',
    `  unreviewed: ${summary.review_status_counts.unreviewed}`,
    `  reviewed: ${summary.review_status_counts.reviewed}`,
    `  suspect: ${summary.review_status_counts.suspect}`,
    `  suppressed: ${summary.review_status_counts.suppressed}`,
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

  lines.push('', 'Project health:');
  for (const project of summary.projects) {
    lines.push(
      `  ${project.project_slug || 'unscoped'}: total=${project.total_memory_rows}, suspect=${project.suspect_rows}, low_confidence=${project.low_confidence_rows}, duplicates=${project.duplicate_candidate_rows}, verdict=${project.health_verdict}`,
    );
  }

  return lines.join('\n');
}

function renderProjectHealthTable(payload) {
  const lines = [
    'CrispyBrain Project Memory Health',
    `Generated at: ${payload.generated_at}`,
    `Scope: ${payload.scope_project_slug || 'all projects'}`,
  ];

  if (payload.projects.length === 0) {
    lines.push('(no matching project rows)');
    return lines.join('\n');
  }

  for (const project of payload.projects) {
    lines.push(
      [
        '',
        `[${project.project_slug || 'unscoped'}] ${project.health_verdict}`,
        `  total_memory_rows: ${project.total_memory_rows}`,
        `  suspect_rows: ${project.suspect_rows}`,
        `  low_confidence_rows: ${project.low_confidence_rows}`,
        `  duplicate_candidate_rows: ${project.duplicate_candidate_rows}`,
        `  source_type_counts: ${JSON.stringify(project.source_type_counts)}`,
        `  review_status_counts: ${JSON.stringify(project.review_status_counts)}`,
        `  recent_ingest_activity: ${JSON.stringify(project.recent_ingest_activity)}`,
        `  recent_review_activity: ${JSON.stringify(project.recent_review_activity)}`,
      ].join('\n'),
    );
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
        `  source_type: ${row.source_type}`,
        `  review_status: ${row.review_status}`,
        `  trust_band: ${row.trust_band}`,
        `  filename: ${row.filename || '(none)'}`,
        `  filepath: ${row.filepath || '(none)'}`,
        `  preview: ${row.content_preview || '(empty)'}`,
        `  reason_flagged: ${row.reason_flagged.length > 0 ? row.reason_flagged.join(', ') : '(none)'}`,
        `  duplicate_candidate: ${row.duplicate_candidate}`,
        `  content_length: ${row.content_length}`,
        `  created_at: ${row.created_at || '(unknown)'}`,
        `  run_id: ${row.run_id || '(none)'}`,
        `  correlation_id: ${row.correlation_id || '(none)'}`,
      ].join('\n'),
    );
  }

  return lines.join('\n\n');
}

function csvEscape(value) {
  if (value === null || value === undefined) {
    return '';
  }
  const text = Array.isArray(value) ? value.join(';') : String(value);
  if (/[",\n]/.test(text)) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

function rowsToCsv(rows) {
  const headers = [
    'id',
    'project_slug',
    'source_type',
    'review_status',
    'trust_band',
    'title',
    'filename',
    'filepath',
    'content_preview',
    'reason_flagged',
    'duplicate_candidate',
    'content_length',
    'created_at',
    'run_id',
    'correlation_id',
  ];
  const lines = [headers.join(',')];
  for (const row of rows) {
    lines.push(headers.map((header) => csvEscape(row[header])).join(','));
  }
  return lines.join('\n');
}

function timestampToken() {
  const iso = new Date().toISOString();
  return iso.replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z');
}

function defaultExportPath(projectSlug, format) {
  const scope = projectSlug || 'all-projects';
  return path.join(DEFAULT_EXPORT_DIR, `crispybrain-suspect-${scope}-${timestampToken()}.${format}`);
}

function defaultSnapshotPath(projectSlug) {
  const scope = projectSlug || 'all-projects';
  return path.join(DEFAULT_METRICS_DIR, `crispybrain-memory-health-${scope}-${timestampToken()}.json`);
}

function writeOutput(output, outputPath) {
  if (!outputPath) {
    process.stdout.write(`${output}\n`);
    return null;
  }
  const resolved = ensureInsideRepo(outputPath);
  ensureDirectory(path.dirname(resolved));
  fs.writeFileSync(resolved, `${output}\n`, 'utf8');
  process.stdout.write(`Wrote ${resolved}\n`);
  return resolved;
}

function updateReviewStatus(containerName, options) {
  const idsSql = options.ids.join(',');
  const noteValue = options.reviewNote ? sqlLiteral(options.reviewNote) : 'NULL';
  const nowValue = sqlLiteral(new Date().toISOString());
  const statusValue = sqlLiteral(options.reviewStatus);
  const sql = [
    'WITH updated AS (',
    '  UPDATE memories',
    '  SET metadata_json = jsonb_strip_nulls(',
    '    jsonb_set(',
    '      jsonb_set(',
    '        jsonb_set(COALESCE(metadata_json, \'{}\'::jsonb), \'{review_status}\', to_jsonb(',
    `          ${statusValue}::text`,
    '        ), true),',
    `        '{review_updated_at}', to_jsonb(${nowValue}::text), true`,
    '      ),',
    `      '{review_note}', to_jsonb(${noteValue}::text), true`,
    '    )',
    '  )',
    `  WHERE id = ANY(ARRAY[${idsSql}]::bigint[])`,
    '  RETURNING id, title, metadata_json',
    ')',
    'SELECT COALESCE(json_agg(row_to_json(updated))::text, \'[]\') FROM updated;',
  ].join(' ');

  const raw = runPsql(containerName, sql);
  const updated = JSON.parse(raw || '[]').map((row) => ({
    id: Number(row.id),
    title: row.title,
    review_status: normalizeReviewStatus(row.metadata_json?.review_status),
    review_updated_at: normalizeTimestamp(row.metadata_json?.review_updated_at),
    review_note: normalizeString(row.metadata_json?.review_note),
  }));
  return {
    updated_count: updated.length,
    rows: updated,
  };
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }

  const containerName = detectContainer('crispy-ai-lab-postgres-1', 'ai-postgres');

  if (options.mode === 'set-review-status') {
    const payload = updateReviewStatus(containerName, options);
    const output = options.format === 'json'
      ? JSON.stringify(payload, null, 2)
      : renderRowsTable(payload.rows, `Updated review status to ${options.reviewStatus}`);
    writeOutput(output, options.outputPath);
    return;
  }

  const rows = classifyRows(queryRows(containerName));
  const filteredRows = applyProjectFilter(rows, options.projectSlug);
  const suspectRows = filteredRows.filter((row) => row.classification === 'suspect' || row.trust_band === 'low' || row.trust_band === 'suppressed');
  const cleanRows = filteredRows.filter((row) => row.classification === 'clean');
  const summary = buildOverallSummary(filteredRows);
  const projectHealth = buildProjectHealthPayload(rows, options.projectSlug);

  let payload;
  let text;
  let outputPath = options.outputPath;

  if (options.mode === 'summary') {
    payload = summary;
    text = renderSummaryTable(summary);
  } else if (options.mode === 'project-health') {
    payload = projectHealth;
    text = renderProjectHealthTable(projectHealth);
  } else if (options.mode === 'suspect') {
    payload = maybeLimit(suspectRows, options.limit);
    text = renderRowsTable(payload, 'Suspect / low-confidence memory rows');
  } else if (options.mode === 'clean') {
    payload = maybeLimit(cleanRows, options.limit);
    text = renderRowsTable(payload, 'Clean memory rows');
  } else if (options.mode === 'export-suspect') {
    payload = suspectRows;
    if (!outputPath) {
      const extension = options.format === 'csv' ? 'csv' : 'json';
      outputPath = defaultExportPath(options.projectSlug, extension);
    }
    text = options.format === 'csv' ? rowsToCsv(payload) : JSON.stringify(payload, null, 2);
  } else if (options.mode === 'snapshot-health') {
    payload = projectHealth;
    if (!outputPath) {
      outputPath = defaultSnapshotPath(options.projectSlug);
    }
    text = JSON.stringify(payload, null, 2);
  } else {
    fail(`Unhandled mode: ${options.mode}`);
  }

  const rendered = options.format === 'json' && !['export-suspect', 'snapshot-health'].includes(options.mode)
    ? JSON.stringify(payload, null, 2)
    : text;
  writeOutput(rendered, outputPath);
}

main();
