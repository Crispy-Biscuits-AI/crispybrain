#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/Users/elric/repos/openbrain/scripts/openbrain-test-harness.sh
source "${SCRIPT_DIR}/openbrain-test-harness.sh"

IMPORT_SCRIPT="${SCRIPT_DIR}/import-openbrain-v0_3.sh"
WORKFLOW_ID="openbrain-assistant"
WEBHOOK_URL="http://localhost:5678/webhook/openbrain-assistant"
SESSION_TEST_ID="openbrain-v0-3-session-test"

openbrain_harness_require_command jq
openbrain_harness_require_command curl

[[ -x "${IMPORT_SCRIPT}" ]] || openbrain_harness_fail "Import script is missing or not executable: ${IMPORT_SCRIPT}"

"${IMPORT_SCRIPT}"

openbrain_harness_log "Resetting session test rows"
openbrain_harness_db_query "DELETE FROM openbrain_chat_turns WHERE session_id = '${SESSION_TEST_ID}';" >/dev/null

openbrain_harness_log "Test 1: plain chat request"
openbrain_harness_post_json "${WEBHOOK_URL}" '{"message":"What is OpenBrain?"}'
openbrain_harness_log "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}"
[[ "${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || openbrain_harness_fail "Plain chat request returned HTTP ${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.ok' 'true'
openbrain_harness_assert_json_string_contains "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.answer' 'OpenBrain'
openbrain_harness_assert_json_number_gte "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.retrieval.memory_count' 1

openbrain_harness_log "Test 2: project-aware request"
openbrain_harness_post_json "${WEBHOOK_URL}" '{"message":"How am I planning to build OpenBrain?","project_slug":"alpha","top_k":4}'
openbrain_harness_log "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}"
[[ "${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || openbrain_harness_fail "Project-aware request returned HTTP ${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.ok' 'true'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.project_slug' 'alpha'
openbrain_harness_assert_json_number_gte "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.retrieval.project_match_count' 1
openbrain_harness_assert_json_number_gte "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.sources | length' 1

openbrain_harness_log "Test 3a: first turn in a session"
openbrain_harness_post_json "${WEBHOOK_URL}" "{\"message\":\"What is the OpenBrain architecture?\",\"project_slug\":\"alpha\",\"session_id\":\"${SESSION_TEST_ID}\"}"
openbrain_harness_log "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}"
[[ "${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || openbrain_harness_fail "Session continuity turn 1 returned HTTP ${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.ok' 'true'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.session_id' "${SESSION_TEST_ID}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.session.turn_count_before' '0'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.session.turn_count_after' '2'

openbrain_harness_log "Test 3b: second turn in the same session"
openbrain_harness_post_json "${WEBHOOK_URL}" "{\"message\":\"What is the next planned workflow?\",\"project_slug\":\"alpha\",\"session_id\":\"${SESSION_TEST_ID}\"}"
openbrain_harness_log "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}"
[[ "${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || openbrain_harness_fail "Session continuity turn 2 returned HTTP ${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.ok' 'true'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.session_id' "${SESSION_TEST_ID}"
openbrain_harness_assert_json_number_gte "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.session.turn_count_before' 2
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.session.history_used' 'true'

SESSION_ROW_COUNT="$(openbrain_harness_db_query "SELECT COUNT(*) FROM openbrain_chat_turns WHERE session_id = '${SESSION_TEST_ID}';")"
SESSION_ROW_COUNT="$(printf '%s' "${SESSION_ROW_COUNT}" | tr -d '[:space:]')"
openbrain_harness_log "session row count: ${SESSION_ROW_COUNT}"
[[ "${SESSION_ROW_COUNT}" =~ ^[0-9]+$ ]] || openbrain_harness_fail "Session row count was not numeric"
(( SESSION_ROW_COUNT >= 4 )) || openbrain_harness_fail "Expected at least 4 stored chat turns for ${SESSION_TEST_ID}, got ${SESSION_ROW_COUNT}"

openbrain_harness_log "Test 4: invalid input"
openbrain_harness_post_json "${WEBHOOK_URL}" '{"message":""}'
openbrain_harness_log "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}"
[[ "${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || openbrain_harness_fail "Invalid-input request returned HTTP ${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.ok' 'false'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.error.code' 'INVALID_INPUT'

openbrain_harness_log "Test 5: empty retrieval"
openbrain_harness_post_json "${WEBHOOK_URL}" '{"message":"zxqv orphan nebula wrench pineapple ninety-nine","project_slug":"alpha"}'
openbrain_harness_log "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}"
[[ "${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || openbrain_harness_fail "Empty-retrieval request returned HTTP ${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.ok' 'true'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.retrieval.empty' 'true'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.sources | length' '0'
openbrain_harness_assert_json_string_contains "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.answer' 'do not have enough stored memory'

openbrain_harness_log "Checking n8n execution records"
openbrain_harness_assert_execution_success "${WORKFLOW_ID}"

openbrain_harness_pass "OpenBrain v0.3 assistant imported, activated, and passed plain chat, project-aware, session continuity, invalid input, and empty retrieval tests"
