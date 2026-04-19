#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

detect_container() {
  local preferred="$1"
  local fallback="$2"
  if docker ps --format '{{.Names}}' | grep -Fxq "${preferred}"; then
    printf '%s\n' "${preferred}"
    return 0
  fi
  printf '%s\n' "${fallback}"
}

export CRISPYBRAIN_HARNESS_N8N_CONTAINER="${CRISPYBRAIN_HARNESS_N8N_CONTAINER:-$(detect_container 'crispy-ai-lab-n8n-1' 'ai-n8n')}"
export CRISPYBRAIN_HARNESS_DB_CONTAINER="${CRISPYBRAIN_HARNESS_DB_CONTAINER:-$(detect_container 'crispy-ai-lab-postgres-1' 'ai-postgres')}"
export CRISPYBRAIN_HARNESS_REST_BASE_URL="${CRISPYBRAIN_HARNESS_REST_BASE_URL:-http://localhost:5678/rest}"

# shellcheck source=./crispybrain-test-harness.sh
source "${SCRIPT_DIR}/crispybrain-test-harness.sh"

crispybrain_harness_require_command jq
crispybrain_harness_require_command curl
crispybrain_harness_require_command node
crispybrain_harness_require_command docker

find_suspect_ids() {
  local rows_json
  rows_json="$(docker exec "${CRISPYBRAIN_HARNESS_DB_CONTAINER}" psql -U n8n -d n8n -t -A -c "SELECT COALESCE(json_agg(row_to_json(t))::text, '[]') FROM (SELECT id, content, metadata_json->>'filepath' AS filepath, metadata_json->>'project_slug' AS project_slug FROM memories ORDER BY id) t;")"
  ROWS_JSON="${rows_json}" node - <<'EOF'
const rows = JSON.parse(process.env.ROWS_JSON || '[]');
const isUsableContent = (content) => {
  const value = typeof content === 'string' ? content.trim() : '';
  if (value.length < 20) return false;
  if (value.includes('\uFFFD')) return false;
  const alphaCount = (value.match(/[A-Za-z]/g) ?? []).length;
  if (alphaCount < 12) return false;
  const safeCount = (value.match(/[A-Za-z0-9\s.,:;!?()'"_\/-]/g) ?? []).length;
  return safeCount / value.length >= 0.7;
};

const suspectIds = rows.filter((row) => !isUsableContent(row.content)).map((row) => Number(row.id));
process.stdout.write(JSON.stringify(suspectIds));
EOF
}

assert_nonempty_string() {
  local value="$1"
  local label="$2"
  [[ -n "${value}" && "${value}" != "null" ]] || crispybrain_harness_fail "Expected non-empty ${label}"
}

assert_no_suspect_sources() {
  local response_json="$1"
  local suspect_ids_json="$2"
  RESPONSE_JSON="${response_json}" SUSPECT_IDS_JSON="${suspect_ids_json}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const suspectIds = new Set(JSON.parse(process.env.SUSPECT_IDS_JSON));
const sources = Array.isArray(response.sources) ? response.sources : [];
const overlaps = sources.filter((source) => suspectIds.has(Number(source.id))).map((source) => source.id);
if (overlaps.length > 0) {
  console.error(`Suspicious source ids returned by assistant: ${overlaps.join(', ')}`);
  process.exit(1);
}
if (sources.some((source) => typeof source.snippet === 'string' && source.snippet.includes('\uFFFD'))) {
  console.error('Assistant returned a source snippet containing replacement characters');
  process.exit(1);
}
EOF
}

assert_source_contains_filename() {
  local response_json="$1"
  local expected_filename="$2"
  RESPONSE_JSON="${response_json}" EXPECTED_FILENAME="${expected_filename}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const expected = process.env.EXPECTED_FILENAME;
const sources = Array.isArray(response.sources) ? response.sources : [];
if (!sources.some((source) => typeof source.title === 'string' && source.title.includes(expected))) {
  console.error(`Expected at least one source title to include ${expected}`);
  process.exit(1);
}
EOF
}

AUTH_COOKIE="$(crispybrain_harness_mint_auth_cookie)"
assert_nonempty_string "${AUTH_COOKIE}" 'auth cookie'

SUSPECT_IDS_JSON="$(find_suspect_ids)"
crispybrain_harness_log "Suspect memory ids under the v0.5.1 rule: ${SUSPECT_IDS_JSON}"

crispybrain_harness_log "Test 1: invalid ingest still rejects with a structured trace"
crispybrain_harness_register_listener 'ingest' 'Return Failure Payload' "${AUTH_COOKIE}"
crispybrain_harness_post_json \
  'http://localhost:5678/webhook-test/ingest' \
  '{"filepath":"/tmp/crispybrain-v0_5_1-invalid.txt","filename":"crispybrain-v0_5_1-invalid.txt","content":"   ","project_slug":"alpha","correlation_id":"corr-v051-invalid"}'
crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
[[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Invalid ingest returned HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].ok' 'false'
crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].error.code' 'EMPTY_CONTENT'
crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].trace.correlation_id' 'corr-v051-invalid'
crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].trace.status' 'rejected'

for cycle in 1 2; do
  token="cb-v051-cycle-${cycle}-$(date +%s)-${RANDOM}"
  filepath="/tmp/${token}.txt"
  filename="${token}.txt"
  ingest_correlation="corr-v051-ingest-${cycle}"
  assistant_correlation="corr-v051-assistant-${cycle}"
  payload="$(jq -cn \
    --arg filepath "${filepath}" \
    --arg filename "${filename}" \
    --arg token "${token}" \
    --arg correlation_id "${ingest_correlation}" \
    '{filepath: $filepath, filename: $filename, content: ("CrispyBrain v0.5.1 stability cycle note. Unique token " + $token + ". This text is intentionally plain ASCII and should remain retrievable without corruption."), project_slug: "alpha", modifiedEpoch: 1713531000, correlation_id: $correlation_id}')"

  crispybrain_harness_log "Test 2.${cycle}a: valid ingest cycle ${cycle}"
  crispybrain_harness_register_listener 'ingest' 'Return Success Payload' "${AUTH_COOKIE}"
  crispybrain_harness_post_json 'http://localhost:5678/webhook-test/ingest' "${payload}"
  crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
  [[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Valid ingest cycle ${cycle} returned HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].ok' 'true'
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].trace.correlation_id' "${ingest_correlation}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].trace.stage' 'completed'
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].trace.status' 'succeeded'
  ingest_run_id="$(crispybrain_harness_json_get "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].trace.run_id')"
  assert_nonempty_string "${ingest_run_id}" "ingest run_id for cycle ${cycle}"

  crispybrain_harness_log "Test 2.${cycle}b: duplicate ingest cycle ${cycle}"
  crispybrain_harness_register_listener 'ingest' 'Return Failure Payload' "${AUTH_COOKIE}"
  crispybrain_harness_post_json 'http://localhost:5678/webhook-test/ingest' "${payload}"
  crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
  [[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Duplicate ingest cycle ${cycle} returned HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].duplicate_detected' 'true'
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].error.code' 'DUPLICATE_INGEST'
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].trace.status' 'rejected'

  crispybrain_harness_log "Test 2.${cycle}c: assistant retrieval cycle ${cycle}"
  assistant_payload="$(jq -cn --arg token "${token}" --arg correlation_id "${assistant_correlation}" '{message: ("What note mentions " + $token + "?"), project_slug: "alpha", correlation_id: $correlation_id}')"
  crispybrain_harness_post_json 'http://localhost:5678/webhook/assistant' "${assistant_payload}"
  crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
  [[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Assistant cycle ${cycle} returned HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.trace.correlation_id' "${assistant_correlation}"
  assistant_run_id="$(crispybrain_harness_json_get "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.trace.run_id')"
  assert_nonempty_string "${assistant_run_id}" "assistant run_id for cycle ${cycle}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.ok' 'true'
  assert_source_contains_filename "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" "${filename}"
  assert_no_suspect_sources "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" "${SUSPECT_IDS_JSON}"
done

crispybrain_harness_log 'Test 3: baseline assistant query does not surface suspect rows'
crispybrain_harness_post_json \
  'http://localhost:5678/webhook/assistant' \
  '{"message":"What is CrispyBrain?","project_slug":"alpha","correlation_id":"corr-v051-baseline"}'
crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
[[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Baseline assistant query returned HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.trace.correlation_id' 'corr-v051-baseline'
assert_no_suspect_sources "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" "${SUSPECT_IDS_JSON}"

crispybrain_harness_pass 'CrispyBrain v0.5.1 repeated ingest and assistant cycles preserved tracing, duplicate protection, invalid rejection, and suspect-row filtering'
