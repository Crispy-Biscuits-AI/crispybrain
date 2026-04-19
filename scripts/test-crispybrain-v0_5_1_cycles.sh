#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MEMORY_INSPECTOR="${SCRIPT_DIR}/inspect-crispybrain-memory.js"
MIN_CYCLES=3
MAX_CYCLES=12
DEFAULT_CYCLES=6

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

assistant_latency_total=0
assistant_latency_min=0
assistant_latency_max=0
assistant_latency_first_total=0
assistant_latency_first_count=0
assistant_latency_second_total=0
assistant_latency_second_count=0

ingest_latency_total=0
ingest_latency_min=0
ingest_latency_max=0
ingest_latency_first_total=0
ingest_latency_first_count=0
ingest_latency_second_total=0
ingest_latency_second_count=0

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
  ./scripts/test-crispybrain-v0_5_1_cycles.sh
  ./scripts/test-crispybrain-v0_5_1_cycles.sh --cycles 6

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

[[ "${cycles_requested}" =~ ^[0-9]+$ ]] || {
  printf 'FAIL: cycle count must be an integer\n' >&2
  exit 1
}
(( cycles_requested >= MIN_CYCLES && cycles_requested <= MAX_CYCLES )) || {
  printf 'FAIL: cycle count must be between %d and %d\n' "${MIN_CYCLES}" "${MAX_CYCLES}" >&2
  exit 1
}

midpoint=$(( cycles_requested / 2 ))

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

checks_attempted=0
checks_passed=0
cycles_completed=0
initial_summary_json=''
final_summary_json=''
failure_trend='no_failures_observed'
noise_trend='not_evaluated'
latency_drift='not_evaluated'

emit_summary() {
  local exit_code="$?"
  local checks_failed=$(( checks_attempted - checks_passed ))
  local final_summary="${final_summary_json:-${initial_summary_json}}"
  local initial_total_rows=0
  local initial_suspect_rows=0
  local final_total_rows=0
  local final_suspect_rows=0
  local assistant_avg=0
  local ingest_avg=0
  local assistant_first_avg=0
  local assistant_second_avg=0
  local ingest_first_avg=0
  local ingest_second_avg=0

  if [[ -n "${initial_summary_json}" ]]; then
    initial_total_rows="$(printf '%s' "${initial_summary_json}" | jq -r '.total_rows')"
    initial_suspect_rows="$(printf '%s' "${initial_summary_json}" | jq -r '.suspect_rows')"
  fi
  if [[ -n "${final_summary}" ]]; then
    final_total_rows="$(printf '%s' "${final_summary}" | jq -r '.total_rows')"
    final_suspect_rows="$(printf '%s' "${final_summary}" | jq -r '.suspect_rows')"
  fi

  if (( cycles_completed > 0 )); then
    assistant_avg=$(( assistant_latency_total / cycles_completed ))
    ingest_avg=$(( ingest_latency_total / cycles_completed ))
  fi
  if (( assistant_latency_first_count > 0 )); then
    assistant_first_avg=$(( assistant_latency_first_total / assistant_latency_first_count ))
  fi
  if (( assistant_latency_second_count > 0 )); then
    assistant_second_avg=$(( assistant_latency_second_total / assistant_latency_second_count ))
  fi
  if (( ingest_latency_first_count > 0 )); then
    ingest_first_avg=$(( ingest_latency_first_total / ingest_latency_first_count ))
  fi
  if (( ingest_latency_second_count > 0 )); then
    ingest_second_avg=$(( ingest_latency_second_total / ingest_latency_second_count ))
  fi

  if (( checks_failed > 0 )); then
    failure_trend='failures_observed'
  fi

  if [[ "${latency_drift}" == 'not_evaluated' ]]; then
    latency_drift='not_material'
  fi

  printf 'SUMMARY: cycles_requested=%s cycles_completed=%s checks_passed=%s checks_failed=%s\n' \
    "${cycles_requested}" "${cycles_completed}" "${checks_passed}" "${checks_failed}"
  printf 'SUMMARY: initial_total_rows=%s final_total_rows=%s initial_suspect_rows=%s final_suspect_rows=%s\n' \
    "${initial_total_rows}" "${final_total_rows}" "${initial_suspect_rows}" "${final_suspect_rows}"
  printf 'SUMMARY: valid_ingest_latency_ms avg=%s min=%s max=%s first_half_avg=%s second_half_avg=%s\n' \
    "${ingest_avg}" "${ingest_latency_min}" "${ingest_latency_max}" "${ingest_first_avg}" "${ingest_second_avg}"
  printf 'SUMMARY: assistant_latency_ms avg=%s min=%s max=%s first_half_avg=%s second_half_avg=%s\n' \
    "${assistant_avg}" "${assistant_latency_min}" "${assistant_latency_max}" "${assistant_first_avg}" "${assistant_second_avg}"
  printf 'SUMMARY: failure_trend=%s noise_trend=%s latency_drift=%s\n' \
    "${failure_trend}" "${noise_trend}" "${latency_drift}"

  if (( exit_code != 0 )); then
    printf 'SUMMARY: partial_run=true\n'
  fi
}

trap emit_summary EXIT

record_latency() {
  local kind="$1"
  local elapsed_ms="$2"
  local cycle_number="$3"

  if [[ "${kind}" == 'assistant' ]]; then
    assistant_latency_total=$(( assistant_latency_total + elapsed_ms ))
    if (( assistant_latency_min == 0 || elapsed_ms < assistant_latency_min )); then
      assistant_latency_min="${elapsed_ms}"
    fi
    if (( elapsed_ms > assistant_latency_max )); then
      assistant_latency_max="${elapsed_ms}"
    fi
    if (( cycle_number <= midpoint )); then
      assistant_latency_first_total=$(( assistant_latency_first_total + elapsed_ms ))
      assistant_latency_first_count=$(( assistant_latency_first_count + 1 ))
    else
      assistant_latency_second_total=$(( assistant_latency_second_total + elapsed_ms ))
      assistant_latency_second_count=$(( assistant_latency_second_count + 1 ))
    fi
  else
    ingest_latency_total=$(( ingest_latency_total + elapsed_ms ))
    if (( ingest_latency_min == 0 || elapsed_ms < ingest_latency_min )); then
      ingest_latency_min="${elapsed_ms}"
    fi
    if (( elapsed_ms > ingest_latency_max )); then
      ingest_latency_max="${elapsed_ms}"
    fi
    if (( cycle_number <= midpoint )); then
      ingest_latency_first_total=$(( ingest_latency_first_total + elapsed_ms ))
      ingest_latency_first_count=$(( ingest_latency_first_count + 1 ))
    else
      ingest_latency_second_total=$(( ingest_latency_second_total + elapsed_ms ))
      ingest_latency_second_count=$(( ingest_latency_second_count + 1 ))
    fi
  fi
}

measure_post_json() {
  local start_ms end_ms
  start_ms="$(now_ms)"
  crispybrain_harness_post_json "$@"
  end_ms="$(now_ms)"
  CRISPYBRAIN_HARNESS_LAST_ELAPSED_MS=$(( end_ms - start_ms ))
}

assert_nonempty_string() {
  local value="$1"
  local label="$2"
  [[ -n "${value}" && "${value}" != "null" ]] || crispybrain_harness_fail "Expected non-empty ${label}"
}

json_get() {
  local json_body="$1"
  local jq_expression="$2"
  printf '%s' "${json_body}" | jq -r "${jq_expression}"
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

refresh_memory_summary() {
  node "${MEMORY_INSPECTOR}" --mode summary --json
}

suspect_ids_from_summary() {
  local summary_json="$1"
  printf '%s' "${summary_json}" | jq -c '.suspect_ids'
}

initial_summary_json="$(refresh_memory_summary)"
suspect_ids_json="$(suspect_ids_from_summary "${initial_summary_json}")"
crispybrain_harness_log "Initial memory summary: ${initial_summary_json}"
crispybrain_harness_log "Suspect memory ids under the v0.5.1 rule: ${suspect_ids_json}"

AUTH_COOKIE="$(crispybrain_harness_mint_auth_cookie)"
assert_nonempty_string "${AUTH_COOKIE}" 'auth cookie'

for cycle in $(seq 1 "${cycles_requested}"); do
  token="cb-v051-cycle-${cycle}-$(date +%s)-${RANDOM}"
  anchor_token="cbv051anchor${cycle}$(date +%s)${RANDOM}"
  filepath="/tmp/${token}.txt"
  filename="${token}.txt"
  invalid_correlation="corr-v051-invalid-${cycle}"
  ingest_correlation="corr-v051-ingest-${cycle}"
  assistant_correlation="corr-v051-assistant-${cycle}"

  checks_attempted=$(( checks_attempted + 1 ))
  crispybrain_harness_log "Test ${cycle}.1: invalid ingest rejects with structured trace"
  crispybrain_harness_register_listener 'ingest' 'Return Failure Payload' "${AUTH_COOKIE}"
  measure_post_json \
    'http://localhost:5678/webhook-test/ingest' \
    "{\"filepath\":\"/tmp/${token}-invalid.txt\",\"filename\":\"${token}-invalid.txt\",\"content\":\"   \",\"project_slug\":\"alpha\",\"correlation_id\":\"${invalid_correlation}\"}"
  crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
  [[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Invalid ingest cycle ${cycle} returned HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].ok' 'false'
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].error.code' 'EMPTY_CONTENT'
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].trace.correlation_id' "${invalid_correlation}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].trace.status' 'rejected'
  checks_passed=$(( checks_passed + 1 ))

  payload="$(jq -cn \
    --arg filepath "${filepath}" \
    --arg filename "${filename}" \
    --arg token "${token}" \
    --arg anchor_token "${anchor_token}" \
    --arg correlation_id "${ingest_correlation}" \
    '{filepath: $filepath, filename: $filename, content: ("CrispyBrain v0.5.1 stability cycle note. Unique token " + $token + ". Stable anchor " + $anchor_token + ". Repeat stable anchor " + $anchor_token + " to keep retrieval deterministic without corruption."), project_slug: "alpha", modifiedEpoch: 1713531000, correlation_id: $correlation_id}')"

  checks_attempted=$(( checks_attempted + 1 ))
  crispybrain_harness_log "Test ${cycle}.2: valid ingest cycle ${cycle}"
  crispybrain_harness_register_listener 'ingest' 'Return Success Payload' "${AUTH_COOKIE}"
  measure_post_json 'http://localhost:5678/webhook-test/ingest' "${payload}"
  crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
  [[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Valid ingest cycle ${cycle} returned HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].ok' 'true'
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].trace.correlation_id' "${ingest_correlation}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].trace.stage' 'completed'
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].trace.status' 'succeeded'
  ingest_run_id="$(crispybrain_harness_json_get "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].trace.run_id')"
  assert_nonempty_string "${ingest_run_id}" "ingest run_id for cycle ${cycle}"
  record_latency 'ingest' "${CRISPYBRAIN_HARNESS_LAST_ELAPSED_MS}" "${cycle}"
  checks_passed=$(( checks_passed + 1 ))

  checks_attempted=$(( checks_attempted + 1 ))
  crispybrain_harness_log "Test ${cycle}.3: duplicate ingest cycle ${cycle}"
  crispybrain_harness_register_listener 'ingest' 'Return Failure Payload' "${AUTH_COOKIE}"
  measure_post_json 'http://localhost:5678/webhook-test/ingest' "${payload}"
  crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
  [[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Duplicate ingest cycle ${cycle} returned HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].duplicate_detected' 'true'
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].error.code' 'DUPLICATE_INGEST'
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.[0].trace.status' 'rejected'
  checks_passed=$(( checks_passed + 1 ))

  checks_attempted=$(( checks_attempted + 1 ))
  crispybrain_harness_log "Test ${cycle}.4: assistant retrieval cycle ${cycle}"
  assistant_payload="$(jq -cn --arg anchor_token "${anchor_token}" --arg correlation_id "${assistant_correlation}" '{message: ("Which note contains stable anchor " + $anchor_token + "?"), project_slug: "alpha", correlation_id: $correlation_id}')"
  measure_post_json 'http://localhost:5678/webhook/assistant' "${assistant_payload}"
  crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
  [[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Assistant cycle ${cycle} returned HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.trace.correlation_id' "${assistant_correlation}"
  assistant_run_id="$(crispybrain_harness_json_get "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.trace.run_id')"
  assert_nonempty_string "${assistant_run_id}" "assistant run_id for cycle ${cycle}"
  crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.ok' 'true'
  assert_source_contains_filename "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" "${filename}"
  assert_no_suspect_sources "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" "${suspect_ids_json}"
  record_latency 'assistant' "${CRISPYBRAIN_HARNESS_LAST_ELAPSED_MS}" "${cycle}"
  checks_passed=$(( checks_passed + 1 ))
  cycles_completed=$(( cycles_completed + 1 ))
done

checks_attempted=$(( checks_attempted + 1 ))
crispybrain_harness_log 'Test baseline: assistant query does not surface suspect rows'
measure_post_json \
  'http://localhost:5678/webhook/assistant' \
  '{"message":"What is CrispyBrain?","project_slug":"alpha","correlation_id":"corr-v051-baseline"}'
crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
[[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Baseline assistant query returned HTTP ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
crispybrain_harness_assert_json_equals "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" '.trace.correlation_id' 'corr-v051-baseline'
assert_no_suspect_sources "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" "${suspect_ids_json}"
checks_passed=$(( checks_passed + 1 ))

final_summary_json="$(refresh_memory_summary)"
crispybrain_harness_log "Final memory summary: ${final_summary_json}"

initial_total_rows="$(json_get "${initial_summary_json}" '.total_rows')"
initial_suspect_rows="$(json_get "${initial_summary_json}" '.suspect_rows')"
final_total_rows="$(json_get "${final_summary_json}" '.total_rows')"
final_suspect_rows="$(json_get "${final_summary_json}" '.suspect_rows')"
expected_total_rows=$(( initial_total_rows + cycles_completed ))
[[ "${final_total_rows}" == "${expected_total_rows}" ]] || crispybrain_harness_fail "Expected total memory rows to grow from ${initial_total_rows} to ${expected_total_rows}, got ${final_total_rows}"
[[ "${final_suspect_rows}" == "${initial_suspect_rows}" ]] || crispybrain_harness_fail "Expected suspect row count to remain ${initial_suspect_rows}, got ${final_suspect_rows}"

noise_trend='no_new_suspect_rows_or_source_leaks'
assistant_first_avg=0
assistant_second_avg=0
ingest_first_avg=0
ingest_second_avg=0
if (( assistant_latency_first_count > 0 )); then
  assistant_first_avg=$(( assistant_latency_first_total / assistant_latency_first_count ))
fi
if (( assistant_latency_second_count > 0 )); then
  assistant_second_avg=$(( assistant_latency_second_total / assistant_latency_second_count ))
fi
if (( ingest_latency_first_count > 0 )); then
  ingest_first_avg=$(( ingest_latency_first_total / ingest_latency_first_count ))
fi
if (( ingest_latency_second_count > 0 )); then
  ingest_second_avg=$(( ingest_latency_second_total / ingest_latency_second_count ))
fi

if (( assistant_latency_second_count > 0 && assistant_latency_first_count > 0 )) && \
   (( assistant_second_avg > assistant_first_avg + 500 )) && \
   (( assistant_second_avg * 10 > assistant_first_avg * 15 )); then
  latency_drift='assistant_latency_materially_higher_in_later_cycles'
elif (( ingest_latency_second_count > 0 && ingest_latency_first_count > 0 )) && \
     (( ingest_second_avg > ingest_first_avg + 500 )) && \
     (( ingest_second_avg * 10 > ingest_first_avg * 15 )); then
  latency_drift='ingest_latency_materially_higher_in_later_cycles'
else
  latency_drift='not_material'
fi

crispybrain_harness_pass "CrispyBrain repeated ingest and assistant cycles preserved tracing, duplicate protection, invalid rejection, and suspect-row filtering across ${cycles_completed} cycles"
