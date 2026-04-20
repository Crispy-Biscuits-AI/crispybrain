#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MEMORY_INSPECTOR="${SCRIPT_DIR}/inspect-crispybrain-memory.js"
ASSISTANT_WORKFLOW_PATH="${REPO_ROOT}/workflows/assistant.json"
DEMO_WORKFLOW_PATH="${REPO_ROOT}/workflows/crispybrain-demo.json"
INGEST_WORKFLOW_PATH="${REPO_ROOT}/workflows/ingest.json"
SEED_SPEC_PATH="${REPO_ROOT}/seed-data/crispybrain-v0_9-eval-seed.json"
ASSISTANT_CONTAINER_PATH="/tmp/crispybrain-assistant-v0_9-test.json"
DEMO_CONTAINER_PATH="/tmp/crispybrain-demo-v0_9-test.json"
INGEST_CONTAINER_PATH="/tmp/crispybrain-ingest-v0_9-test.json"

detect_container() {
  local preferred="$1"
  local fallback="$2"
  if docker ps --format '{{.Names}}' | grep -Fxq "${preferred}"; then
    printf '%s\n' "${preferred}"
    return 0
  fi
  printf '%s\n' "${fallback}"
}

assert_nonempty_string() {
  local value="$1"
  local label="$2"
  [[ -n "${value}" && "${value}" != "null" ]] || crispybrain_harness_fail "Expected non-empty ${label}"
}

inspect_json() {
  node "${MEMORY_INSPECTOR}" "$@" --json
}

seed_json_value() {
  local key="$1"
  local field="$2"
  jq -r --arg key "${key}" --arg field "${field}" '.notes[] | select(.key == $key) | .[$field]' "${SEED_SPEC_PATH}"
}

latest_memory_id_for_filepath() {
  local filepath="$1"
  docker exec "${CRISPYBRAIN_HARNESS_DB_CONTAINER}" psql -U n8n -d n8n -At -c "SELECT id FROM memories WHERE metadata_json->>'filepath' = '${filepath}' ORDER BY id DESC LIMIT 1;"
}

now_ms() {
  node -e 'process.stdout.write(String(Date.now()))'
}

measure_post_json() {
  local start_ms end_ms
  start_ms="$(now_ms)"
  crispybrain_harness_post_json "$@"
  end_ms="$(now_ms)"
  CRISPYBRAIN_HARNESS_LAST_ELAPSED_MS=$(( end_ms - start_ms ))
}

workflow_version_id() {
  local workflow_id="$1"
  crispybrain_harness_get_json "${CRISPYBRAIN_HARNESS_REST_BASE_URL}/workflows/${workflow_id}" -H "Cookie: ${CRISPYBRAIN_HARNESS_COOKIE_NAME}=${AUTH_COOKIE}"
  [[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Could not fetch workflow details for ${workflow_id}"
  crispybrain_harness_json_get "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.data.versionId'
}

activate_repo_workflow() {
  local workflow_id="$1"
  local version_id
  version_id="$(workflow_version_id "${workflow_id}")"
  [[ -n "${version_id}" && "${version_id}" != "null" ]] || crispybrain_harness_fail "Workflow ${workflow_id} did not expose a versionId"
  crispybrain_harness_activate_workflow "${workflow_id}" "${AUTH_COOKIE}" "$(jq -cn --arg versionId "${version_id}" '{versionId: $versionId}')"
}

ingest_runtime_note() {
  local filepath="$1"
  local filename="$2"
  local content="$3"
  local correlation_id="$4"

  crispybrain_harness_register_listener 'ingest' 'Return Success Payload' "${AUTH_COOKIE}"
  measure_post_json 'http://localhost:5678/webhook-test/ingest' "$(jq -cn \
    --arg filepath "${filepath}" \
    --arg filename "${filename}" \
    --arg content "${content}" \
    --arg correlation_id "${correlation_id}" \
    '{filepath: $filepath, filename: $filename, content: $content, project_slug: "alpha", modifiedEpoch: 1713534000, correlation_id: $correlation_id}')"

  [[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Ingest failed for ${filename} with HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].ok' 'true'
}

mark_reviewed() {
  local row_id="$1"
  local note="$2"
  local update_json
  update_json="$(inspect_json --mode set-review-status --ids "${row_id}" --status reviewed --note "${note}")"
  [[ "$(printf '%s' "${update_json}" | jq -r '.updated_count')" == "1" ]] || crispybrain_harness_fail "Expected review-status update to affect row ${row_id}"
}

summarize_response() {
  local response_json="$1"
  RESPONSE_JSON="${response_json}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const sources = Array.isArray(response.sources) ? response.sources : [];
const topSource = sources[0] ?? null;
const summary = {
  ranking_mode: response.trace?.ranking_mode ?? null,
  answer_mode: response.answer_mode ?? null,
  conflict_flag: response.conflict_flag ?? false,
  grounding_status: response.grounding?.status ?? null,
  memory_count: response.retrieval?.memory_count ?? null,
  retrieved_candidate_count: Array.isArray(response.retrieved_candidates) ? response.retrieved_candidates.length : 0,
  top_source_title: topSource?.title ?? null,
};
process.stdout.write(JSON.stringify(summary));
EOF
}

evaluate_anchor_lookup() {
  local response_json="$1"
  RESPONSE_JSON="${response_json}" EXPECTED_TITLE="${ANCHOR_FILENAME}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const top = Array.isArray(response.sources) ? response.sources[0] ?? {} : {};
const ok = response.ok === true
  && response.answer_mode === 'direct'
  && response.trace?.ranking_mode === 'anchor'
  && typeof top.title === 'string'
  && top.title.includes(process.env.EXPECTED_TITLE)
  && typeof response.answer === 'string'
  && response.answer.includes(process.env.EXPECTED_TITLE);
process.exit(ok ? 0 : 1);
EOF
}

evaluate_general_single() {
  local response_json="$1"
  RESPONSE_JSON="${response_json}" EXPECTED_TITLE="${GENERAL_SINGLE_FILENAME}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const top = Array.isArray(response.sources) ? response.sources[0] ?? {} : {};
const ok = response.ok === true
  && response.answer_mode === 'direct'
  && response.conflict_flag !== true
  && response.grounding?.status === 'grounded'
  && typeof top.title === 'string'
  && top.title.includes(process.env.EXPECTED_TITLE);
process.exit(ok ? 0 : 1);
EOF
}

evaluate_general_multi() {
  local response_json="$1"
  RESPONSE_JSON="${response_json}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const ok = response.ok === true
  && response.answer_mode === 'direct'
  && response.conflict_flag !== true
  && Number(response.retrieval?.memory_count ?? 0) >= 2
  && Array.isArray(response.selected_sources)
  && response.selected_sources.length >= 2
  && Number(response.grounding?.supporting_source_count ?? 0) >= 2;
process.exit(ok ? 0 : 1);
EOF
}

evaluate_conflict() {
  local response_json="$1"
  RESPONSE_JSON="${response_json}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const answer = typeof response.answer === 'string' ? response.answer : '';
const ok = response.ok === true
  && response.answer_mode === 'conflict'
  && response.conflict_flag === true
  && Array.isArray(response.sources)
  && response.sources.length >= 2
  && answer.includes('amber-9')
  && answer.includes('cobalt-3');
process.exit(ok ? 0 : 1);
EOF
}

evaluate_short_fact() {
  local response_json="$1"
  RESPONSE_JSON="${response_json}" EXPECTED_TITLE="${SHORT_FACT_FILENAME}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const top = Array.isArray(response.sources) ? response.sources[0] ?? {} : {};
const ok = response.ok === true
  && response.answer_mode === 'direct'
  && response.conflict_flag !== true
  && typeof top.title === 'string'
  && top.title.includes(process.env.EXPECTED_TITLE)
  && Array.isArray(response.retrieved_candidates)
  && response.retrieved_candidates.length >= 1;
process.exit(ok ? 0 : 1);
EOF
}

evaluate_weak_evidence() {
  local response_json="$1"
  RESPONSE_JSON="${response_json}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const ok = response.ok === true
  && response.answer_mode === 'insufficient'
  && response.retrieval?.empty === true
  && typeof response.answer === 'string'
  && response.answer.includes('I do not have enough stored memory')
  && Array.isArray(response.retrieved_candidates)
  && response.retrieved_candidates.length >= 1;
process.exit(ok ? 0 : 1);
EOF
}

run_case() {
  local case_id="$1"
  local intent="$2"
  local query="$3"
  local expected_behavior="$4"
  local evaluator="$5"

  total_cases=$(( total_cases + 1 ))
  crispybrain_harness_log "CASE ${case_id} [${intent}]"
  crispybrain_harness_log "  query: ${query}"
  crispybrain_harness_log "  expected: ${expected_behavior}"

  measure_post_json 'http://localhost:5678/webhook/assistant' "$(jq -cn \
    --arg query "${query}" \
    --arg correlation_id "corr-v090-${case_id}" \
    --arg session_id "cb-v090-${case_id}" \
    '{message: $query, project_slug: "alpha", correlation_id: $correlation_id, session_id: $session_id, top_k: 8}')"

  local diagnostic
  diagnostic="$(summarize_response "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}")"

  if [[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" != "200" ]]; then
    failed_cases+=("${case_id}")
    crispybrain_harness_log "  result: FAIL"
    crispybrain_harness_log "  diagnostic: http_status=${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS} ${diagnostic}"
    return
  fi

  if "${evaluator}" "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"; then
    passed_cases=$(( passed_cases + 1 ))
    crispybrain_harness_log "  result: PASS"
  else
    failed_cases+=("${case_id}")
    crispybrain_harness_log "  result: FAIL"
  fi

  crispybrain_harness_log "  diagnostic: ${diagnostic}"
}

cleanup_files=()
cleanup() {
  local exit_code="$?"
  for file_path in "${cleanup_files[@]:-}"; do
    rm -f "${file_path}"
  done
  rmdir "${REPO_ROOT}/seed-data/runtime" 2>/dev/null || true
  exit "${exit_code}"
}
trap cleanup EXIT

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
[[ -f "${DEMO_WORKFLOW_PATH}" ]] || crispybrain_harness_fail "Demo workflow export was not found: ${DEMO_WORKFLOW_PATH}"
[[ -f "${INGEST_WORKFLOW_PATH}" ]] || crispybrain_harness_fail "Ingest workflow export was not found: ${INGEST_WORKFLOW_PATH}"
[[ -f "${SEED_SPEC_PATH}" ]] || crispybrain_harness_fail "Seed spec was not found: ${SEED_SPEC_PATH}"

crispybrain_harness_copy_workflow "${ASSISTANT_WORKFLOW_PATH}" "${ASSISTANT_CONTAINER_PATH}" 'assistant'
crispybrain_harness_import_workflow "${ASSISTANT_CONTAINER_PATH}" 'assistant'
crispybrain_harness_copy_workflow "${DEMO_WORKFLOW_PATH}" "${DEMO_CONTAINER_PATH}" 'crispybrain-demo'
crispybrain_harness_import_workflow "${DEMO_CONTAINER_PATH}" 'crispybrain-demo'
crispybrain_harness_copy_workflow "${INGEST_WORKFLOW_PATH}" "${INGEST_CONTAINER_PATH}" 'ingest'
crispybrain_harness_import_workflow "${INGEST_CONTAINER_PATH}" 'ingest'

workflow_list="$(crispybrain_harness_list_workflows)"
crispybrain_harness_assert_workflow_visible 'assistant' "${workflow_list}"
crispybrain_harness_assert_workflow_visible 'crispybrain-demo' "${workflow_list}"
crispybrain_harness_assert_workflow_visible 'ingest' "${workflow_list}"

AUTH_COOKIE="$(crispybrain_harness_mint_auth_cookie)"
assert_nonempty_string "${AUTH_COOKIE}" 'auth cookie'

activate_repo_workflow 'assistant'
activate_repo_workflow 'crispybrain-demo'

RUNTIME_DIR="${REPO_ROOT}/seed-data/runtime"
mkdir -p "${RUNTIME_DIR}"

RUN_TOKEN="cbv090$(date +%s)${RANDOM}"

seed_note() {
  local key="$1"
  local filename_prefix content reviewed filename filepath row_id uppercase_key var_name
  filename_prefix="$(seed_json_value "${key}" 'filename_prefix')"
  content="$(seed_json_value "${key}" 'content')"
  reviewed="$(seed_json_value "${key}" 'reviewed')"
  filename="${filename_prefix}-${RUN_TOKEN}.txt"
  filepath="${RUNTIME_DIR}/${filename}"
  cleanup_files+=("${filepath}")
  ingest_runtime_note "${filepath}" "${filename}" "${content}" "corr-v090-${key}-ingest"
  row_id="$(latest_memory_id_for_filepath "${filepath}")"
  assert_nonempty_string "${row_id}" "${key} row id"
  if [[ "${reviewed}" == "true" ]]; then
    mark_reviewed "${row_id}" "v0.9 evaluation note ${key}"
  fi
  uppercase_key="$(printf '%s' "${key}" | tr '[:lower:]' '[:upper:]')"
  var_name="${uppercase_key}_FILENAME"
  printf -v "${var_name}" '%s' "${filename}"
}

seed_note anchor_exact
seed_note general_single
seed_note general_agree_a
seed_note general_agree_b
seed_note conflict_a
seed_note conflict_b
seed_note short_fact
seed_note weak_unreviewed

ANCHOR_FILENAME="${ANCHOR_EXACT_FILENAME}"
GENERAL_SINGLE_FILENAME="${GENERAL_SINGLE_FILENAME}"
SHORT_FACT_FILENAME="${SHORT_FACT_FILENAME}"

total_cases=0
passed_cases=0
failed_cases=()

run_case 'eval-01' 'exact anchor lookup' 'Which note contains "CB-4096"?' 'anchor retrieval returns the exact anchor note first' evaluate_anchor_lookup
run_case 'eval-02' 'generalized single-note query' 'How does the delta guide improve retrieval for ids?' 'generalized single-note answer stays direct and grounded' evaluate_general_single
run_case 'eval-03' 'generalized multi-note query' 'What does maple brief say operators should check before trusting an answer?' 'multiple agreeing notes survive into the answer' evaluate_general_multi
run_case 'eval-04' 'conflicting notes' 'What is the beacon protocol?' 'conflict mode surfaces both claims with sources' evaluate_conflict
run_case 'eval-05' 'short factual sparse query' 'CB-2048' 'short factual note is recovered through the upgraded retrieval path' evaluate_short_fact
run_case 'eval-06' 'weak evidence query' 'What does echo marker mean?' 'weak evidence falls back to the insufficient-memory answer' evaluate_weak_evidence

failed_count="${#failed_cases[@]}"
crispybrain_harness_log "SUMMARY: evaluation_cases_total=${total_cases} evaluation_cases_passed=${passed_cases} evaluation_cases_failed=${failed_count}"
crispybrain_harness_log "SUMMARY: likely_failure_point=assistant retrieval ranking, lexical fallback merge, or conflict routing"
crispybrain_harness_log "SUMMARY: next_debug_step=curl -sS -H 'Content-Type: application/json' -d '{\"message\":\"What is the beacon protocol?\",\"project_slug\":\"alpha\",\"top_k\":8}' http://localhost:5678/webhook/assistant | jq '{answer_mode,conflict_flag,conflict_details,retrieval,grounding,sources,retrieved_candidates}'"

if (( failed_count > 0 )); then
  crispybrain_harness_fail "v0.9 evaluation pack failed case(s): ${failed_cases[*]}"
fi

crispybrain_harness_pass "CrispyBrain v0.9 verified the 6-case retrieval and conflict pack"
