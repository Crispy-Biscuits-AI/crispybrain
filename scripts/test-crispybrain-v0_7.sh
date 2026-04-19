#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MEMORY_INSPECTOR="${SCRIPT_DIR}/inspect-crispybrain-memory.js"
ASSISTANT_WORKFLOW_PATH="${REPO_ROOT}/workflows/assistant.json"
ASSISTANT_CONTAINER_PATH="/tmp/crispybrain-assistant-v0_7-test.json"
MIN_CYCLES=3
MAX_CYCLES=12
DEFAULT_CYCLES=4

detect_container() {
  local preferred="$1"
  local fallback="$2"
  if docker ps --format '{{.Names}}' | grep -Fxq "${preferred}"; then
    printf '%s\n' "${preferred}"
    return 0
  fi
  printf '%s\n' "${fallback}"
}

now_ms() {
  node -e 'process.stdout.write(String(Date.now()))'
}

json_get() {
  local json_body="$1"
  local jq_expression="$2"
  printf '%s' "${json_body}" | jq -r "${jq_expression}"
}

assert_nonempty_string() {
  local value="$1"
  local label="$2"
  [[ -n "${value}" && "${value}" != "null" ]] || crispybrain_harness_fail "Expected non-empty ${label}"
}

assert_file_exists() {
  local file_path="$1"
  [[ -f "${file_path}" ]] || crispybrain_harness_fail "Expected file to exist: ${file_path}"
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

assert_source_filename_has_review_status() {
  local response_json="$1"
  local expected_filename="$2"
  local expected_review_status="$3"
  RESPONSE_JSON="${response_json}" EXPECTED_FILENAME="${expected_filename}" EXPECTED_REVIEW_STATUS="${expected_review_status}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const expectedFilename = process.env.EXPECTED_FILENAME;
const expectedReviewStatus = process.env.EXPECTED_REVIEW_STATUS;
const sources = Array.isArray(response.sources) ? response.sources : [];
const matchingSource = sources.find((source) => typeof source.title === 'string' && source.title.includes(expectedFilename));
if (!matchingSource) {
  console.error(`Expected at least one source title to include ${expectedFilename}`);
  process.exit(1);
}
if (matchingSource.review_status !== expectedReviewStatus) {
  console.error(`Expected source ${expectedFilename} to report review_status ${expectedReviewStatus}, got ${matchingSource.review_status}`);
  process.exit(1);
}
EOF
}

assert_no_source_filename() {
  local response_json="$1"
  local blocked_filename="$2"
  RESPONSE_JSON="${response_json}" BLOCKED_FILENAME="${blocked_filename}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const blocked = process.env.BLOCKED_FILENAME;
const sources = Array.isArray(response.sources) ? response.sources : [];
if (sources.some((source) => typeof source.title === 'string' && source.title.includes(blocked))) {
  console.error(`Unexpected source title included suppressed filename ${blocked}`);
  process.exit(1);
}
EOF
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

memory_review_status_by_id() {
  local memory_id="$1"
  docker exec "${CRISPYBRAIN_HARNESS_DB_CONTAINER}" psql -U n8n -d n8n -At -c "SELECT COALESCE(NULLIF(metadata_json->>'review_status', ''), 'unreviewed') FROM memories WHERE id = ${memory_id} LIMIT 1;"
}

assert_response_source_review_statuses_match_db() {
  local response_json="$1"
  while IFS=$'\t' read -r source_id source_status; do
    [[ -n "${source_id}" ]] || continue
    local db_status
    db_status="$(memory_review_status_by_id "${source_id}" | tr -d '[:space:]')"
    [[ -n "${db_status}" ]] || crispybrain_harness_fail "Could not load DB review_status for retrieved source id ${source_id}"
    [[ "${source_status}" == "${db_status}" ]] || crispybrain_harness_fail "Retrieved source id ${source_id} reported review_status '${source_status}', expected DB value '${db_status}'"
  done < <(RESPONSE_JSON="${response_json}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const sources = Array.isArray(response.sources) ? response.sources : [];
for (const source of sources) {
  if (source && source.id !== undefined && source.id !== null) {
    process.stdout.write(`${source.id}\t${source.review_status ?? ''}\n`);
  }
}
EOF
)
}

normalize_assistant_response_for_consistency() {
  local response_json="$1"
  RESPONSE_JSON="${response_json}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const normalizeSource = (source) => ({
  id: source?.id ?? null,
  title: source?.title ?? null,
  project_slug: source?.project_slug ?? null,
  source_type: source?.source_type ?? null,
  category: source?.category ?? null,
  created_at: source?.created_at ?? null,
  review_status: source?.review_status ?? null,
  project_match: source?.project_match ?? null,
  content_length: source?.content_length ?? null,
  chunk_size_band: source?.chunk_size_band ?? null,
  duplicate_candidate: source?.duplicate_candidate ?? null,
  trust_band: source?.trust_band ?? null,
  confidence_band: source?.confidence_band ?? null,
  uncertainty_indicator: source?.uncertainty_indicator ?? null,
  uncertainty_reasons: Array.isArray(source?.uncertainty_reasons) ? source.uncertainty_reasons : [],
  quality_flags: Array.isArray(source?.quality_flags) ? source.quality_flags : [],
  similarity: source?.similarity ?? null,
  lexical_overlap: source?.lexical_overlap ?? null,
  snippet: source?.snippet ?? null,
});
const normalized = {
  ok: response.ok ?? null,
  answer: response.answer ?? null,
  query: response.query ?? null,
  project_slug: response.project_slug ?? null,
  top_k: response.top_k ?? null,
  retrieval: response.retrieval ?? null,
  trust: response.trust ?? null,
  sources: Array.isArray(response.sources) ? response.sources.map(normalizeSource) : [],
  context_preview: response.context_preview ?? null,
};
process.stdout.write(JSON.stringify(normalized));
EOF
}

json_sha256() {
  local value="$1"
  VALUE_TO_HASH="${value}" node - <<'EOF'
const crypto = require('crypto');
process.stdout.write(crypto.createHash('sha256').update(process.env.VALUE_TO_HASH).digest('hex'));
EOF
}

measure_post_json() {
  local start_ms end_ms
  start_ms="$(now_ms)"
  crispybrain_harness_post_json "$@"
  end_ms="$(now_ms)"
  CRISPYBRAIN_HARNESS_LAST_ELAPSED_MS=$(( end_ms - start_ms ))
}

cleanup_files=()
cleanup() {
  local exit_code="$?"
  for file_path in "${cleanup_files[@]:-}"; do
    rm -f "${file_path}"
  done
  rmdir "${REPO_ROOT}/seed-data/exports/runtime" 2>/dev/null || true
  rmdir "${REPO_ROOT}/seed-data/metrics/runtime" 2>/dev/null || true
  rmdir "${REPO_ROOT}/seed-data/runtime" 2>/dev/null || true
  exit "${exit_code}"
}
trap cleanup EXIT

cycles_requested="${DEFAULT_CYCLES}"
while (( $# > 0 )); do
  case "$1" in
    --cycles|-n)
      cycles_requested="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Usage:
  ./scripts/test-crispybrain-v0_7.sh
  ./scripts/test-crispybrain-v0_7.sh --cycles 4

Cycle count must stay within the safe range 3..12.
EOF
      exit 0
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        cycles_requested="$1"
        shift
      else
        printf 'FAIL: Unknown argument: %s\n' "$1" >&2
        exit 1
      fi
      ;;
  esac
done

[[ "${cycles_requested}" =~ ^[0-9]+$ ]] || crispybrain_harness_fail "cycle count must be an integer"
(( cycles_requested >= MIN_CYCLES && cycles_requested <= MAX_CYCLES )) || crispybrain_harness_fail "cycle count must be between ${MIN_CYCLES} and ${MAX_CYCLES}"

export CRISPYBRAIN_HARNESS_N8N_CONTAINER="${CRISPYBRAIN_HARNESS_N8N_CONTAINER:-$(detect_container 'crispy-ai-lab-n8n-1' 'ai-n8n')}"
export CRISPYBRAIN_HARNESS_DB_CONTAINER="${CRISPYBRAIN_HARNESS_DB_CONTAINER:-$(detect_container 'crispy-ai-lab-postgres-1' 'ai-postgres')}"
export CRISPYBRAIN_HARNESS_REST_BASE_URL="${CRISPYBRAIN_HARNESS_REST_BASE_URL:-http://localhost:5678/rest}"

# shellcheck source=./crispybrain-test-harness.sh
source "${SCRIPT_DIR}/crispybrain-test-harness.sh"

crispybrain_harness_require_command jq
crispybrain_harness_require_command curl
crispybrain_harness_require_command node
crispybrain_harness_require_command docker
[[ -x "${MEMORY_INSPECTOR}" ]] || crispybrain_harness_fail "Memory inspection tool is not executable: ${MEMORY_INSPECTOR}"
[[ -f "${ASSISTANT_WORKFLOW_PATH}" ]] || crispybrain_harness_fail "Assistant workflow export was not found: ${ASSISTANT_WORKFLOW_PATH}"

crispybrain_harness_copy_workflow "${ASSISTANT_WORKFLOW_PATH}" "${ASSISTANT_CONTAINER_PATH}" 'assistant'
crispybrain_harness_import_workflow "${ASSISTANT_CONTAINER_PATH}" 'assistant'
workflow_list="$(crispybrain_harness_list_workflows)"
crispybrain_harness_assert_workflow_visible 'assistant' "${workflow_list}"

checks_attempted=0
checks_passed=0
cycles_completed=0
ingest_latency_total=0
assistant_latency_total=0
ingest_latency_min=0
ingest_latency_max=0
assistant_latency_min=0
assistant_latency_max=0
consistency_passes_requested="${cycles_requested}"
consistency_passes_completed=0
consistency_drift_count=0
anchor_consistency_passes_completed=0
anchor_consistency_drift_count=0
anchor_consistency_baseline_hash=""
exact_consistency_passes_completed=0
exact_consistency_drift_count=0
exact_consistency_baseline_hash=""

record_latency() {
  local kind="$1"
  local elapsed_ms="$2"
  if [[ "${kind}" == 'ingest' ]]; then
    ingest_latency_total=$(( ingest_latency_total + elapsed_ms ))
    if (( ingest_latency_min == 0 || elapsed_ms < ingest_latency_min )); then
      ingest_latency_min="${elapsed_ms}"
    fi
    if (( elapsed_ms > ingest_latency_max )); then
      ingest_latency_max="${elapsed_ms}"
    fi
  else
    assistant_latency_total=$(( assistant_latency_total + elapsed_ms ))
    if (( assistant_latency_min == 0 || elapsed_ms < assistant_latency_min )); then
      assistant_latency_min="${elapsed_ms}"
    fi
    if (( elapsed_ms > assistant_latency_max )); then
      assistant_latency_max="${elapsed_ms}"
    fi
  fi
}

inspect_json() {
  node "${MEMORY_INSPECTOR}" "$@" --json
}

latest_memory_id_for_filepath() {
  local filepath="$1"
  docker exec "${CRISPYBRAIN_HARNESS_DB_CONTAINER}" psql -U n8n -d n8n -At -c "SELECT id FROM memories WHERE metadata_json->>'filepath' = '${filepath}' ORDER BY id DESC LIMIT 1;"
}

EXPORT_RUNTIME_DIR="${REPO_ROOT}/seed-data/exports/runtime"
METRICS_RUNTIME_DIR="${REPO_ROOT}/seed-data/metrics/runtime"
NOTE_RUNTIME_DIR="${REPO_ROOT}/seed-data/runtime"
mkdir -p "${EXPORT_RUNTIME_DIR}" "${METRICS_RUNTIME_DIR}" "${NOTE_RUNTIME_DIR}"

initial_project_health="$(inspect_json --mode project-health --project-slug alpha)"
initial_summary="$(inspect_json --mode summary)"
suspect_ids_json="$(printf '%s' "${initial_summary}" | jq -c '.suspect_ids')"
crispybrain_harness_log "Initial summary: ${initial_summary}"
crispybrain_harness_log "Initial project health: ${initial_project_health}"

summary_export_json="${EXPORT_RUNTIME_DIR}/crispybrain-v071-suspect-alpha-initial.json"
summary_export_csv="${EXPORT_RUNTIME_DIR}/crispybrain-v071-suspect-alpha-initial.csv"
snapshot_initial="${METRICS_RUNTIME_DIR}/crispybrain-v071-health-alpha-initial.json"
cleanup_files+=("${summary_export_json}" "${summary_export_csv}" "${snapshot_initial}")

checks_attempted=$(( checks_attempted + 1 ))
node "${MEMORY_INSPECTOR}" --mode export-suspect --project-slug alpha --format json --out "${summary_export_json}" >/dev/null
assert_file_exists "${summary_export_json}"
(( $(jq 'length' "${summary_export_json}") >= 3 )) || crispybrain_harness_fail "Expected at least 3 suspect/low-confidence rows in JSON export"
grep -Fq '"id": 20' "${summary_export_json}" || crispybrain_harness_fail "Expected suspect JSON export to include row id 20"
checks_passed=$(( checks_passed + 1 ))

checks_attempted=$(( checks_attempted + 1 ))
node "${MEMORY_INSPECTOR}" --mode export-suspect --project-slug alpha --format csv --out "${summary_export_csv}" >/dev/null
assert_file_exists "${summary_export_csv}"
grep -Fq 'final-watch-test-6.txt' "${summary_export_csv}" || crispybrain_harness_fail "Expected suspect CSV export to contain final-watch-test-6.txt"
checks_passed=$(( checks_passed + 1 ))

checks_attempted=$(( checks_attempted + 1 ))
node "${MEMORY_INSPECTOR}" --mode snapshot-health --project-slug alpha --out "${snapshot_initial}" >/dev/null
assert_file_exists "${snapshot_initial}"
[[ "$(jq -r '.projects[0].project_slug' "${snapshot_initial}")" == "alpha" ]] || crispybrain_harness_fail "Initial snapshot did not contain alpha project summary"
checks_passed=$(( checks_passed + 1 ))

AUTH_COOKIE="$(crispybrain_harness_mint_auth_cookie)"
assert_nonempty_string "${AUTH_COOKIE}" 'auth cookie'
crispybrain_harness_get_json "${CRISPYBRAIN_HARNESS_REST_BASE_URL}/workflows/assistant" -H "Cookie: ${CRISPYBRAIN_HARNESS_COOKIE_NAME}=${AUTH_COOKIE}"
[[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail 'Could not fetch assistant workflow details after import'
assistant_workflow_version_id="$(crispybrain_harness_json_get "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.data.versionId')"
[[ -n "${assistant_workflow_version_id}" && "${assistant_workflow_version_id}" != 'null' ]] || crispybrain_harness_fail 'Assistant workflow versionId was missing after import'
assistant_activation_payload="$(jq -cn --arg versionId "${assistant_workflow_version_id}" '{versionId: $versionId}')"
crispybrain_harness_activate_workflow 'assistant' "${AUTH_COOKIE}" "${assistant_activation_payload}"

suppressed_anchor="cbv060suppressed$(date +%s)${RANDOM}"
suppressed_filename="cb-v060-suppressed-${suppressed_anchor}.txt"
suppressed_filepath="${NOTE_RUNTIME_DIR}/${suppressed_filename}"
suppressed_payload="$(jq -cn \
  --arg filepath "${suppressed_filepath}" \
  --arg filename "${suppressed_filename}" \
  --arg anchor "${suppressed_anchor}" \
  '{filepath: $filepath, filename: $filename, content: ("CrispyBrain v0.7.1 suppression control note. Suppressed anchor " + $anchor + ". This note should disappear from retrieval after explicit suppression."), project_slug: "alpha", modifiedEpoch: 1713532000, correlation_id: "corr-v060-suppressed-ingest"}')"

crispybrain_harness_log 'Control test: explicit suppressed review state'
crispybrain_harness_register_listener 'ingest' 'Return Success Payload' "${AUTH_COOKIE}"
measure_post_json 'http://localhost:5678/webhook-test/ingest' "${suppressed_payload}"
crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
[[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Suppressed control ingest returned HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
suppressed_row_id="$(latest_memory_id_for_filepath "${suppressed_filepath}")"
assert_nonempty_string "${suppressed_row_id}" 'suppressed control row id'

checks_attempted=$(( checks_attempted + 1 ))
suppressed_review_update="$(inspect_json --mode set-review-status --ids "${suppressed_row_id}" --status suppressed --note 'v0.7.1 control suppression')"
crispybrain_harness_log "Suppressed review update: ${suppressed_review_update}"
[[ "$(printf '%s' "${suppressed_review_update}" | jq -r '.updated_count')" == "1" ]] || crispybrain_harness_fail "Expected suppressed control review update to affect 1 row"
checks_passed=$(( checks_passed + 1 ))

checks_attempted=$(( checks_attempted + 1 ))
measure_post_json 'http://localhost:5678/webhook/assistant' "$(jq -cn --arg anchor "${suppressed_anchor}" '{message: ("Which note contains suppressed anchor " + $anchor + "?"), project_slug: "alpha", correlation_id: "corr-v060-suppressed-check"}')"
crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
[[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Suppressed control assistant query returned HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
assert_no_source_filename "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" "${suppressed_filename}"
checks_passed=$(( checks_passed + 1 ))

for cycle in $(seq 1 "${cycles_requested}"); do
  token="cb-v060-cycle-${cycle}-$(date +%s)-${RANDOM}"
  anchor_token="cbv060anchor${cycle}$(date +%s)${RANDOM}"
  filepath="${NOTE_RUNTIME_DIR}/${token}.txt"
  filename="${token}.txt"
  invalid_correlation="corr-v060-invalid-${cycle}"
  ingest_correlation="corr-v060-ingest-${cycle}"
  assistant_correlation="corr-v060-assistant-${cycle}"
  reviewed_probe_correlation="corr-v060-reviewed-source-${cycle}"

  checks_attempted=$(( checks_attempted + 1 ))
  crispybrain_harness_log "Test ${cycle}.1: invalid ingest rejection"
  crispybrain_harness_register_listener 'ingest' 'Return Failure Payload' "${AUTH_COOKIE}"
  measure_post_json \
    'http://localhost:5678/webhook-test/ingest' \
    "{\"filepath\":\"${NOTE_RUNTIME_DIR}/${token}-invalid.txt\",\"filename\":\"${token}-invalid.txt\",\"content\":\"   \",\"project_slug\":\"alpha\",\"correlation_id\":\"${invalid_correlation}\"}"
  crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
  [[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Invalid ingest cycle ${cycle} returned HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].error.code' 'EMPTY_CONTENT'
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].trace.correlation_id' "${invalid_correlation}"
  checks_passed=$(( checks_passed + 1 ))

  payload="$(jq -cn \
    --arg filepath "${filepath}" \
    --arg filename "${filename}" \
    --arg token "${token}" \
    --arg anchor "${anchor_token}" \
    --arg correlation_id "${ingest_correlation}" \
    '{filepath: $filepath, filename: $filename, content: ("CrispyBrain v0.7.1 anchor policy note. Token " + $token + ". Stable anchor " + $anchor + ". Reviewed knowledge should surface with strong trust metadata."), project_slug: "alpha", modifiedEpoch: 1713533000, correlation_id: $correlation_id}')"

  checks_attempted=$(( checks_attempted + 1 ))
  crispybrain_harness_log "Test ${cycle}.2: valid ingest"
  crispybrain_harness_register_listener 'ingest' 'Return Success Payload' "${AUTH_COOKIE}"
  measure_post_json 'http://localhost:5678/webhook-test/ingest' "${payload}"
  crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
  [[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Valid ingest cycle ${cycle} returned HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].ok' 'true'
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].trace.correlation_id' "${ingest_correlation}"
  record_latency 'ingest' "${CRISPYBRAIN_HARNESS_LAST_ELAPSED_MS}"
  checks_passed=$(( checks_passed + 1 ))

  row_id="$(latest_memory_id_for_filepath "${filepath}")"
  assert_nonempty_string "${row_id}" "row id for cycle ${cycle}"

  checks_attempted=$(( checks_attempted + 1 ))
  review_update="$(inspect_json --mode set-review-status --ids "${row_id}" --status reviewed --note "v0.7.1 cycle ${cycle} review")"
  crispybrain_harness_log "Review update ${cycle}: ${review_update}"
  [[ "$(printf '%s' "${review_update}" | jq -r '.updated_count')" == "1" ]] || crispybrain_harness_fail "Expected review update to affect 1 row for cycle ${cycle}"
  checks_passed=$(( checks_passed + 1 ))

  checks_attempted=$(( checks_attempted + 1 ))
  crispybrain_harness_log "Test ${cycle}.3: duplicate replay rejection"
  crispybrain_harness_register_listener 'ingest' 'Return Failure Payload' "${AUTH_COOKIE}"
  measure_post_json 'http://localhost:5678/webhook-test/ingest' "${payload}"
  crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
  [[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Duplicate ingest cycle ${cycle} returned HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].error.code' 'DUPLICATE_INGEST'
  checks_passed=$(( checks_passed + 1 ))

  checks_attempted=$(( checks_attempted + 1 ))
  crispybrain_harness_log "Test ${cycle}.4: anchor-aware retrieval policy"
  assistant_payload="$(jq -cn --arg anchor "${anchor_token}" --arg correlation_id "${assistant_correlation}" '{message: ("Which note contains stable anchor " + $anchor + "?"), project_slug: "alpha", correlation_id: $correlation_id}')"
  measure_post_json 'http://localhost:5678/webhook/assistant' "${assistant_payload}"
  crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
  [[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Assistant cycle ${cycle} returned HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.trace.correlation_id' "${assistant_correlation}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.trace.ranking_mode' 'anchor'
  crispybrain_harness_assert_json_number_gte "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.retrieval.memory_count' '1'
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.sources[0].trust_band' 'high'
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.sources[0].project_match' 'true'
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.sources[0].review_status' 'reviewed'
  crispybrain_harness_assert_json_string_contains "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.sources[0].title' "${filename}"
  crispybrain_harness_assert_json_string_contains "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.answer' "${filename}"
  crispybrain_harness_assert_json_string_contains "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.sources[0].source_type' 'file_ingest'
  crispybrain_harness_assert_json_number_gte "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.trust.reviewed_source_count' '1'
  assert_response_source_review_statuses_match_db "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
  assert_no_suspect_sources "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" "${suspect_ids_json}"
  record_latency 'assistant' "${CRISPYBRAIN_HARNESS_LAST_ELAPSED_MS}"
  checks_passed=$(( checks_passed + 1 ))

  checks_attempted=$(( checks_attempted + 1 ))
  crispybrain_harness_log "Test ${cycle}.5: deterministic reviewed-row propagation"
  reviewed_probe_payload="$(jq -cn --arg filename "${filename}" --arg correlation_id "${reviewed_probe_correlation}" '{message: ("Which note is named " + $filename + "?"), project_slug: "alpha", correlation_id: $correlation_id, top_k: 8}')"
  measure_post_json 'http://localhost:5678/webhook/assistant' "${reviewed_probe_payload}"
  crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
  [[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Reviewed-row probe cycle ${cycle} returned HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.trace.correlation_id' "${reviewed_probe_correlation}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.trace.ranking_mode' 'anchor'
  crispybrain_harness_assert_json_number_gte "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.trust.reviewed_source_count' '1'
  crispybrain_harness_assert_json_string_contains "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.sources[0].title' "${filename}"
  crispybrain_harness_assert_json_string_contains "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.answer' "${filename}"
  assert_source_contains_filename "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" "${filename}"
  assert_source_filename_has_review_status "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" "${filename}" 'reviewed'
  assert_response_source_review_statuses_match_db "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
  checks_passed=$(( checks_passed + 1 ))

  cycles_completed=$(( cycles_completed + 1 ))
done

checks_attempted=$(( checks_attempted + 1 ))
crispybrain_harness_log "Consistency test: ${consistency_passes_requested} repeated anchor-style assistant passes"
anchor_consistency_baseline=""
for pass in $(seq 1 "${consistency_passes_requested}"); do
  anchor_consistency_session_id="cb-v071-anchor-consistency-session-${pass}-$(date +%s)-${RANDOM}"
  anchor_consistency_correlation="corr-v071-anchor-consistency-${pass}"
  anchor_consistency_payload="$(jq -cn --arg anchor "${anchor_token}" --arg session_id "${anchor_consistency_session_id}" --arg correlation_id "${anchor_consistency_correlation}" '{message: ("Which note contains stable anchor " + $anchor + "?"), project_slug: "alpha", correlation_id: $correlation_id, session_id: $session_id, top_k: 8}')"
  measure_post_json 'http://localhost:5678/webhook/assistant' "${anchor_consistency_payload}"
  crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
  [[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Anchor consistency pass ${pass} returned HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.trace.correlation_id' "${anchor_consistency_correlation}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.trace.ranking_mode' 'anchor'
  crispybrain_harness_assert_json_number_gte "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.trust.reviewed_source_count' '1'
  crispybrain_harness_assert_json_string_contains "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.sources[0].title' "${filename}"
  crispybrain_harness_assert_json_string_contains "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.answer' "${filename}"
  assert_source_contains_filename "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" "${filename}"
  assert_source_filename_has_review_status "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" "${filename}" 'reviewed'
  assert_response_source_review_statuses_match_db "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
  normalized_anchor_consistency_payload="$(normalize_assistant_response_for_consistency "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}")"
  normalized_anchor_consistency_hash="$(json_sha256 "${normalized_anchor_consistency_payload}")"
  crispybrain_harness_log "Anchor consistency pass ${pass}/${consistency_passes_requested}: response_hash=${normalized_anchor_consistency_hash}"
  if [[ -z "${anchor_consistency_baseline}" ]]; then
    anchor_consistency_baseline="${normalized_anchor_consistency_payload}"
    anchor_consistency_baseline_hash="${normalized_anchor_consistency_hash}"
  elif [[ "${normalized_anchor_consistency_payload}" != "${anchor_consistency_baseline}" ]]; then
    anchor_consistency_drift_count=$(( anchor_consistency_drift_count + 1 ))
    crispybrain_harness_log "Anchor consistency drift detected on pass ${pass}: baseline_hash=${anchor_consistency_baseline_hash}, actual_hash=${normalized_anchor_consistency_hash}"
    crispybrain_harness_log "Anchor consistency baseline payload: ${anchor_consistency_baseline}"
    crispybrain_harness_log "Anchor consistency drift payload: ${normalized_anchor_consistency_payload}"
  fi
  anchor_consistency_passes_completed=$(( anchor_consistency_passes_completed + 1 ))
done

checks_attempted=$(( checks_attempted + 1 ))
crispybrain_harness_log "Consistency test: ${consistency_passes_requested} repeated exact filename assistant passes"
exact_consistency_baseline=""
for pass in $(seq 1 "${consistency_passes_requested}"); do
  exact_consistency_session_id="cb-v071-exact-consistency-session-${pass}-$(date +%s)-${RANDOM}"
  exact_consistency_correlation="corr-v071-exact-consistency-${pass}"
  exact_consistency_payload="$(jq -cn --arg filename "${filename}" --arg session_id "${exact_consistency_session_id}" --arg correlation_id "${exact_consistency_correlation}" '{message: ("Which note is named " + $filename + "?"), project_slug: "alpha", correlation_id: $correlation_id, session_id: $session_id, top_k: 8}')"
  measure_post_json 'http://localhost:5678/webhook/assistant' "${exact_consistency_payload}"
  crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
  [[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Exact consistency pass ${pass} returned HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.trace.correlation_id' "${exact_consistency_correlation}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.trace.ranking_mode' 'anchor'
  crispybrain_harness_assert_json_number_gte "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.trust.reviewed_source_count' '1'
  crispybrain_harness_assert_json_string_contains "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.sources[0].title' "${filename}"
  crispybrain_harness_assert_json_string_contains "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.answer' "${filename}"
  assert_source_contains_filename "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" "${filename}"
  assert_source_filename_has_review_status "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" "${filename}" 'reviewed'
  assert_response_source_review_statuses_match_db "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
  normalized_exact_consistency_payload="$(normalize_assistant_response_for_consistency "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}")"
  normalized_exact_consistency_hash="$(json_sha256 "${normalized_exact_consistency_payload}")"
  crispybrain_harness_log "Exact consistency pass ${pass}/${consistency_passes_requested}: response_hash=${normalized_exact_consistency_hash}"
  if [[ -z "${exact_consistency_baseline}" ]]; then
    exact_consistency_baseline="${normalized_exact_consistency_payload}"
    exact_consistency_baseline_hash="${normalized_exact_consistency_hash}"
  elif [[ "${normalized_exact_consistency_payload}" != "${exact_consistency_baseline}" ]]; then
    exact_consistency_drift_count=$(( exact_consistency_drift_count + 1 ))
    crispybrain_harness_log "Exact consistency drift detected on pass ${pass}: baseline_hash=${exact_consistency_baseline_hash}, actual_hash=${normalized_exact_consistency_hash}"
    crispybrain_harness_log "Exact consistency baseline payload: ${exact_consistency_baseline}"
    crispybrain_harness_log "Exact consistency drift payload: ${normalized_exact_consistency_payload}"
  fi
  exact_consistency_passes_completed=$(( exact_consistency_passes_completed + 1 ))
done

consistency_passes_completed=$(( anchor_consistency_passes_completed + exact_consistency_passes_completed ))
consistency_drift_count=$(( anchor_consistency_drift_count + exact_consistency_drift_count ))
[[ "${consistency_drift_count}" == "0" ]] || crispybrain_harness_fail "Consistency test detected ${consistency_drift_count} drifting pass(es) across ${consistency_passes_completed} repeated runs"
checks_passed=$(( checks_passed + 2 ))

checks_attempted=$(( checks_attempted + 1 ))
crispybrain_harness_log 'Demo output test: crispybrain-demo exposes trust and operator hints'
last_anchor="cbv060anchor${cycles_requested}"
demo_payload="$(jq -cn --arg anchor "${anchor_token}" '{question: ("Which note contains stable anchor " + $anchor + "?"), project_slug: "alpha", correlation_id: "corr-v060-demo"}')"
measure_post_json 'http://localhost:5678/webhook/crispybrain-demo' "${demo_payload}"
crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
[[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Demo workflow returned HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.ok' 'true'
crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.operator.health_summary_supported' 'true'
crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.operator.suspect_export_supported' 'true'
crispybrain_harness_assert_json_number_gte "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.trust.reviewed_source_count' '1'
checks_passed=$(( checks_passed + 1 ))

final_project_health="$(inspect_json --mode project-health --project-slug alpha)"
final_summary="$(inspect_json --mode summary)"
snapshot_final="${METRICS_RUNTIME_DIR}/crispybrain-v071-health-alpha-final.json"
cleanup_files+=("${snapshot_final}")

checks_attempted=$(( checks_attempted + 1 ))
node "${MEMORY_INSPECTOR}" --mode snapshot-health --project-slug alpha --out "${snapshot_final}" >/dev/null
assert_file_exists "${snapshot_final}"
[[ "$(jq -r '.projects[0].review_status_counts.reviewed' "${snapshot_final}")" =~ ^[0-9]+$ ]] || crispybrain_harness_fail "Final snapshot did not include reviewed count"
checks_passed=$(( checks_passed + 1 ))

initial_total_rows="$(printf '%s' "${initial_project_health}" | jq -r '.projects[0].total_memory_rows')"
initial_suspect_rows="$(printf '%s' "${initial_project_health}" | jq -r '.projects[0].suspect_rows')"
initial_reviewed_rows="$(printf '%s' "${initial_project_health}" | jq -r '.projects[0].review_status_counts.reviewed')"
final_total_rows="$(printf '%s' "${final_project_health}" | jq -r '.projects[0].total_memory_rows')"
final_suspect_rows="$(printf '%s' "${final_project_health}" | jq -r '.projects[0].suspect_rows')"
final_reviewed_rows="$(printf '%s' "${final_project_health}" | jq -r '.projects[0].review_status_counts.reviewed')"
expected_total_rows=$(( initial_total_rows + cycles_completed + 1 ))

[[ "${final_total_rows}" == "${expected_total_rows}" ]] || crispybrain_harness_fail "Expected alpha total rows to grow from ${initial_total_rows} to ${expected_total_rows}, got ${final_total_rows}"
[[ "${final_suspect_rows}" == "${initial_suspect_rows}" ]] || crispybrain_harness_fail "Expected alpha suspect row count to remain ${initial_suspect_rows}, got ${final_suspect_rows}"
(( final_reviewed_rows >= initial_reviewed_rows + cycles_completed )) || crispybrain_harness_fail "Expected reviewed row count to increase by at least ${cycles_completed}"

checks_failed=$(( checks_attempted - checks_passed ))
printf 'SUMMARY: cycles_requested=%s cycles_completed=%s checks_passed=%s checks_failed=%s\n' \
  "${cycles_requested}" "${cycles_completed}" "${checks_passed}" "${checks_failed}"
printf 'SUMMARY: anchor_consistency_passes_requested=%s anchor_consistency_passes_completed=%s anchor_consistency_drift_count=%s anchor_consistency_baseline_hash=%s\n' \
  "${consistency_passes_requested}" "${anchor_consistency_passes_completed}" "${anchor_consistency_drift_count}" "${anchor_consistency_baseline_hash}"
printf 'SUMMARY: exact_consistency_passes_requested=%s exact_consistency_passes_completed=%s exact_consistency_drift_count=%s exact_consistency_baseline_hash=%s\n' \
  "${consistency_passes_requested}" "${exact_consistency_passes_completed}" "${exact_consistency_drift_count}" "${exact_consistency_baseline_hash}"
printf 'SUMMARY: consistency_passes_completed=%s consistency_drift_count=%s\n' \
  "${consistency_passes_completed}" "${consistency_drift_count}"
printf 'SUMMARY: alpha_total_rows_before=%s alpha_total_rows_after=%s alpha_suspect_rows_before=%s alpha_suspect_rows_after=%s alpha_reviewed_before=%s alpha_reviewed_after=%s\n' \
  "${initial_total_rows}" "${final_total_rows}" "${initial_suspect_rows}" "${final_suspect_rows}" "${initial_reviewed_rows}" "${final_reviewed_rows}"
printf 'SUMMARY: suspect_export_json=%s suspect_export_csv=%s health_snapshot_initial=%s health_snapshot_final=%s\n' \
  "${summary_export_json}" "${summary_export_csv}" "${snapshot_initial}" "${snapshot_final}"
printf 'SUMMARY: valid_ingest_latency_ms avg=%s min=%s max=%s\n' \
  "$(( ingest_latency_total / cycles_completed ))" "${ingest_latency_min}" "${ingest_latency_max}"
printf 'SUMMARY: assistant_latency_ms avg=%s min=%s max=%s\n' \
  "$(( assistant_latency_total / cycles_completed ))" "${assistant_latency_min}" "${assistant_latency_max}"

crispybrain_harness_pass "CrispyBrain v0.7.1 verified anchor-aware retrieval, reviewed-row propagation, trust visibility, suspect export, and metrics snapshots across ${cycles_completed} cycles"
