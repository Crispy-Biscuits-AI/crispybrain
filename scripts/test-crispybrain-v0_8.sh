#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MEMORY_INSPECTOR="${SCRIPT_DIR}/inspect-crispybrain-memory.js"
ASSISTANT_WORKFLOW_PATH="${REPO_ROOT}/workflows/assistant.json"
DEMO_WORKFLOW_PATH="${REPO_ROOT}/workflows/crispybrain-demo.json"
INGEST_WORKFLOW_PATH="${REPO_ROOT}/workflows/ingest.json"
ASSISTANT_CONTAINER_PATH="/tmp/crispybrain-assistant-v0_8-test.json"
DEMO_CONTAINER_PATH="/tmp/crispybrain-demo-v0_8-test.json"
INGEST_CONTAINER_PATH="/tmp/crispybrain-ingest-v0_8-test.json"

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
  grounding_status: response.grounding?.status ?? null,
  weak_grounding: response.grounding?.weak_grounding ?? null,
  supporting_source_count: response.grounding?.supporting_source_count ?? sources.length,
  reviewed_source_count: response.grounding?.reviewed_source_count ?? response.trust?.reviewed_source_count ?? 0,
  memory_count: response.retrieval?.memory_count ?? null,
  strongest_similarity: response.retrieval?.strongest_similarity ?? response.grounding?.strongest_similarity ?? null,
  top_source_id: topSource?.id ?? null,
  top_source_title: topSource?.title ?? null,
  top_source_review_status: topSource?.review_status ?? null,
  top_source_trust_band: topSource?.trust_band ?? null,
};
process.stdout.write(JSON.stringify(summary));
EOF
}

evaluate_semantic_match() {
  local response_json="$1"
  RESPONSE_JSON="${response_json}" EXPECTED_TITLE="${PRIMARY_FILENAME}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const sources = Array.isArray(response.sources) ? response.sources : [];
const top = sources[0] ?? {};
const ok = response.ok === true
  && response.trace?.ranking_mode === 'semantic'
  && Number(response.retrieval?.memory_count ?? 0) >= 1
  && typeof top.title === 'string'
  && top.title.includes(process.env.EXPECTED_TITLE);
process.exit(ok ? 0 : 1);
EOF
}

evaluate_exact_phrase_match() {
  local response_json="$1"
  RESPONSE_JSON="${response_json}" EXPECTED_TITLE="${PRIMARY_FILENAME}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const sources = Array.isArray(response.sources) ? response.sources : [];
const top = sources[0] ?? {};
const ok = response.ok === true
  && response.trace?.ranking_mode === 'anchor'
  && typeof top.title === 'string'
  && top.title.includes(process.env.EXPECTED_TITLE)
  && typeof response.answer === 'string'
  && response.answer.includes(process.env.EXPECTED_TITLE);
process.exit(ok ? 0 : 1);
EOF
}

evaluate_weak_query() {
  local response_json="$1"
  RESPONSE_JSON="${response_json}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const ok = response.ok === true
  && Number(response.retrieval?.memory_count ?? 0) >= 1
  && response.grounding?.status === 'weak'
  && response.grounding?.weak_grounding === true
  && typeof response.grounding?.note === 'string'
  && response.grounding.note.length > 0;
process.exit(ok ? 0 : 1);
EOF
}

evaluate_no_strong_match() {
  local response_json="$1"
  RESPONSE_JSON="${response_json}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const ok = response.ok === true
  && response.retrieval?.empty === true
  && Number(response.retrieval?.memory_count ?? 0) === 0
  && response.grounding?.status === 'none'
  && response.grounding?.weak_grounding === true;
process.exit(ok ? 0 : 1);
EOF
}

evaluate_distractor_match() {
  local response_json="$1"
  RESPONSE_JSON="${response_json}" EXPECTED_TITLE="${DISTRACTOR_FILENAME}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const sources = Array.isArray(response.sources) ? response.sources : [];
const top = sources[0] ?? {};
const ok = response.ok === true
  && response.trace?.ranking_mode === 'anchor'
  && typeof top.title === 'string'
  && top.title.includes(process.env.EXPECTED_TITLE)
  && typeof response.answer === 'string'
  && response.answer.includes(process.env.EXPECTED_TITLE);
process.exit(ok ? 0 : 1);
EOF
}

evaluate_multi_memory() {
  local response_json="$1"
  RESPONSE_JSON="${response_json}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const ok = response.ok === true
  && Number(response.retrieval?.memory_count ?? 0) >= 2
  && Number(response.grounding?.supporting_source_count ?? 0) >= 2
  && Number(response.trust?.reviewed_source_count ?? 0) >= 2
  && response.grounding?.status !== 'none';
process.exit(ok ? 0 : 1);
EOF
}

evaluate_grounding_visibility() {
  local response_json="$1"
  RESPONSE_JSON="${response_json}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const sources = Array.isArray(response.sources) ? response.sources : [];
const top = sources[0] ?? {};
const ok = response.ok === true
  && typeof response.grounding?.note === 'string'
  && response.grounding.note.length > 0
  && typeof response.debug?.grounding_status === 'string'
  && response.debug.grounding_status.length > 0
  && typeof top.id === 'number'
  && typeof top.trust_band === 'string'
  && Object.prototype.hasOwnProperty.call(top, 'similarity')
  && response.operator?.evaluation_pack_hint === './scripts/test-crispybrain-v0_8.sh';
process.exit(ok ? 0 : 1);
EOF
}

evaluate_regression_query() {
  local response_json="$1"
  RESPONSE_JSON="${response_json}" node - <<'EOF'
const response = JSON.parse(process.env.RESPONSE_JSON);
const sources = Array.isArray(response.sources) ? response.sources : [];
const top = sources[0] ?? {};
const ok = response.ok === true
  && response.trace?.ranking_mode === 'semantic'
  && Number(response.retrieval?.memory_count ?? 0) >= 1
  && typeof top.snippet === 'string'
  && top.snippet.includes('Text files are ingested through the local watch path');
process.exit(ok ? 0 : 1);
EOF
}

run_case() {
  local case_id="$1"
  local intent="$2"
  local query="$3"
  local expected_behavior="$4"
  local url="$5"
  local payload="$6"
  local evaluator="$7"

  total_cases=$(( total_cases + 1 ))
  crispybrain_harness_log "CASE ${case_id} [${intent}]"
  crispybrain_harness_log "  query: ${query}"
  crispybrain_harness_log "  expected: ${expected_behavior}"

  measure_post_json "${url}" "${payload}"
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

RUN_TOKEN="cbv080$(date +%s)${RANDOM}"
PRIMARY_FILENAME="cb-v080-primary-${RUN_TOKEN}.txt"
PRIMARY_FILEPATH="${RUNTIME_DIR}/${PRIMARY_FILENAME}"
DISTRACTOR_FILENAME="cb-v080-distractor-${RUN_TOKEN}.txt"
DISTRACTOR_FILEPATH="${RUNTIME_DIR}/${DISTRACTOR_FILENAME}"
MULTI_A_FILENAME="cb-v080-amber-a-${RUN_TOKEN}.txt"
MULTI_A_FILEPATH="${RUNTIME_DIR}/${MULTI_A_FILENAME}"
MULTI_B_FILENAME="cb-v080-amber-b-${RUN_TOKEN}.txt"
MULTI_B_FILEPATH="${RUNTIME_DIR}/${MULTI_B_FILENAME}"
WEAK_FILENAME="cb-v080-weak-${RUN_TOKEN}.txt"
WEAK_FILEPATH="${RUNTIME_DIR}/${WEAK_FILENAME}"
cleanup_files+=("${PRIMARY_FILEPATH}" "${DISTRACTOR_FILEPATH}" "${MULTI_A_FILEPATH}" "${MULTI_B_FILEPATH}" "${WEAK_FILEPATH}")

ingest_runtime_note \
  "${PRIMARY_FILEPATH}" \
  "${PRIMARY_FILENAME}" \
  "CrispyBrain v0.8 trust and evaluation release note. Exact phrase saffron lattice bridge. The release helps operators by exposing grounding notes, reviewed source visibility, and low-confidence warnings." \
  "corr-v080-primary-ingest"
PRIMARY_ROW_ID="$(latest_memory_id_for_filepath "${PRIMARY_FILEPATH}")"
assert_nonempty_string "${PRIMARY_ROW_ID}" 'primary row id'
mark_reviewed "${PRIMARY_ROW_ID}" 'v0.8 evaluation primary note'

ingest_runtime_note \
  "${DISTRACTOR_FILEPATH}" \
  "${DISTRACTOR_FILENAME}" \
  "CrispyBrain v0.8 distractor note. Exact phrase saffron lattice bracket. This note exists to verify near-neighbor and distractor retrieval behavior." \
  "corr-v080-distractor-ingest"
DISTRACTOR_ROW_ID="$(latest_memory_id_for_filepath "${DISTRACTOR_FILEPATH}")"
assert_nonempty_string "${DISTRACTOR_ROW_ID}" 'distractor row id'
mark_reviewed "${DISTRACTOR_ROW_ID}" 'v0.8 evaluation distractor note'

ingest_runtime_note \
  "${MULTI_A_FILEPATH}" \
  "${MULTI_A_FILENAME}" \
  "Amber archive note A. Amber archive says the operator evaluation pack runs exactly eight cases and checks semantic retrieval, exact phrase matches, and regressions." \
  "corr-v080-multi-a-ingest"
MULTI_A_ROW_ID="$(latest_memory_id_for_filepath "${MULTI_A_FILEPATH}")"
assert_nonempty_string "${MULTI_A_ROW_ID}" 'multi A row id'
mark_reviewed "${MULTI_A_ROW_ID}" 'v0.8 evaluation multi note A'

ingest_runtime_note \
  "${MULTI_B_FILEPATH}" \
  "${MULTI_B_FILENAME}" \
  "Amber archive note B. Amber archive also tells operators to inspect memory ids, trust bands, and weak-grounding notes before relying on an answer." \
  "corr-v080-multi-b-ingest"
MULTI_B_ROW_ID="$(latest_memory_id_for_filepath "${MULTI_B_FILEPATH}")"
assert_nonempty_string "${MULTI_B_ROW_ID}" 'multi B row id'
mark_reviewed "${MULTI_B_ROW_ID}" 'v0.8 evaluation multi note B'

ingest_runtime_note \
  "${WEAK_FILEPATH}" \
  "${WEAK_FILENAME}" \
  "Echo signal note. Echo signal means a single unreviewed memory should be treated cautiously and inspected before trust is assumed. Echo signal is the weak-grounding caution phrase in this evaluation pack." \
  "corr-v080-weak-ingest"
WEAK_ROW_ID="$(latest_memory_id_for_filepath "${WEAK_FILEPATH}")"
assert_nonempty_string "${WEAK_ROW_ID}" 'weak row id'

NO_MATCH_QUERY="zzqxjv plorbn frantix"

total_cases=0
passed_cases=0
failed_cases=()

run_case \
  'eval-01' \
  'semantic match' \
  'How does the trust and evaluation release help operators?' \
  'semantic retrieval returns at least one matching source from the v0.8 pack' \
  'http://localhost:5678/webhook/assistant' \
  "$(jq -cn '{message: "How does the trust and evaluation release help operators?", project_slug: "alpha", correlation_id: "corr-v080-eval-01", session_id: "cb-v080-eval-01"}')" \
  evaluate_semantic_match

run_case \
  'eval-02' \
  'exact phrase match' \
  'Which note contains "saffron lattice bridge"?' \
  'anchor retrieval returns the primary exact-phrase note first' \
  'http://localhost:5678/webhook/assistant' \
  "$(jq -cn '{message: "Which note contains \"saffron lattice bridge\"?", project_slug: "alpha", correlation_id: "corr-v080-eval-02", session_id: "cb-v080-eval-02", top_k: 8}')" \
  evaluate_exact_phrase_match

run_case \
  'eval-03' \
  'ambiguity / weak query' \
  'Tell me about echo signal' \
  'response is explicit about weak grounding instead of pretending high confidence' \
  'http://localhost:5678/webhook/assistant' \
  "$(jq -cn '{message: "Tell me about echo signal", project_slug: "alpha", correlation_id: "corr-v080-eval-03", session_id: "cb-v080-eval-03"}')" \
  evaluate_weak_query

run_case \
  'eval-04' \
  'no-strong-match query' \
  "${NO_MATCH_QUERY}" \
  'response stays honest when no strong supporting memory is retrieved' \
  'http://localhost:5678/webhook/assistant' \
  "$(jq -cn --arg query "${NO_MATCH_QUERY}" '{message: $query, project_slug: "alpha", correlation_id: "corr-v080-eval-04", session_id: "cb-v080-eval-04"}')" \
  evaluate_no_strong_match

run_case \
  'eval-05' \
  'near-neighbor / distractor query' \
  'Which note contains "saffron lattice bracket"?' \
  'anchor retrieval selects the distractor note when the query matches the distractor phrase' \
  'http://localhost:5678/webhook/assistant' \
  "$(jq -cn '{message: "Which note contains \"saffron lattice bracket\"?", project_slug: "alpha", correlation_id: "corr-v080-eval-05", session_id: "cb-v080-eval-05", top_k: 8}')" \
  evaluate_distractor_match

run_case \
  'eval-06' \
  'multi-memory style query' \
  'What does amber archive say operators should inspect?' \
  'response surfaces multiple supporting sources for the shared amber-archive topic' \
  'http://localhost:5678/webhook/assistant' \
  "$(jq -cn '{message: "What does amber archive say operators should inspect?", project_slug: "alpha", correlation_id: "corr-v080-eval-06", session_id: "cb-v080-eval-06", top_k: 8}')" \
  evaluate_multi_memory

run_case \
  'eval-07' \
  'grounding visibility check' \
  'How does the trust and evaluation release help operators?' \
  'demo response exposes grounding note, supporting-source summary, and source evidence fields' \
  'http://localhost:5678/webhook/crispybrain-demo' \
  "$(jq -cn '{question: "How does the trust and evaluation release help operators?", project_slug: "alpha", correlation_id: "corr-v080-eval-07", session_id: "cb-v080-eval-07"}')" \
  evaluate_grounding_visibility

run_case \
  'eval-08' \
  'regression-style query' \
  'How does CrispyBrain ingest text files?' \
  'existing CrispyBrain alpha behavior still returns a grounded retrieval-backed answer' \
  'http://localhost:5678/webhook/assistant' \
  "$(jq -cn '{message: "How does CrispyBrain ingest text files?", project_slug: "alpha", correlation_id: "corr-v080-eval-08", session_id: "cb-v080-eval-08"}')" \
  evaluate_regression_query

failed_count="${#failed_cases[@]}"
crispybrain_harness_log "SUMMARY: evaluation_cases_total=${total_cases} evaluation_cases_passed=${passed_cases} evaluation_cases_failed=${failed_count}"
crispybrain_harness_log "SUMMARY: likely_failure_point=workflow import or activation drift in assistant/crispybrain-demo before evaluation"
crispybrain_harness_log "SUMMARY: next_debug_step=curl -sS -H 'Content-Type: application/json' -d '{\"message\":\"How does the trust and evaluation release help operators?\",\"project_slug\":\"alpha\"}' http://localhost:5678/webhook/assistant | jq '{grounding,retrieval,top_source:(.sources[0] // null),trace}'"

if (( failed_count > 0 )); then
  crispybrain_harness_fail "v0.8 evaluation pack failed case(s): ${failed_cases[*]}"
fi

crispybrain_harness_pass "CrispyBrain v0.8 verified the 8-case trust and evaluation pack"
