#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/Users/elric/repos/openbrain/scripts/openbrain-test-harness.sh
source "${SCRIPT_DIR}/openbrain-test-harness.sh"

IMPORT_SCRIPT="${SCRIPT_DIR}/import-openbrain-v0_3.sh"
WORKFLOW_ID="openbrain-assistant"
WEBHOOK_URL="http://localhost:5678/webhook/openbrain-assistant"
SESSION_TEST_ID="openbrain-v0-3-session-test"
UI_PATH="${SCRIPT_DIR}/../docs/openbrain-v0.3-chat.html"
DOC_PATH="${SCRIPT_DIR}/../docs/openbrain-v0.3.md"
README_PATH="${SCRIPT_DIR}/../README.md"
LEGACY_WEBHOOK_URL="http://localhost:5678/webhook"

openbrain_harness_require_command jq
openbrain_harness_require_command curl
openbrain_harness_require_command node

[[ -x "${IMPORT_SCRIPT}" ]] || openbrain_harness_fail "Import script is missing or not executable: ${IMPORT_SCRIPT}"
[[ -f "${UI_PATH}" ]] || openbrain_harness_fail "UI file is missing: ${UI_PATH}"
[[ -f "${DOC_PATH}" ]] || openbrain_harness_fail "v0.3 docs file is missing: ${DOC_PATH}"
[[ -f "${README_PATH}" ]] || openbrain_harness_fail "README is missing: ${README_PATH}"

openbrain_harness_log "Test 0: WebUI and docs endpoint contract"
node - <<'EOF'
const fs = require('fs');
const path = require('path');

const repoRoot = process.cwd();
const expectedEndpoint = 'http://localhost:5678/webhook/openbrain-assistant';
const legacyEndpoint = 'http://localhost:5678/webhook';
const ui = fs.readFileSync(path.join(repoRoot, 'docs/openbrain-v0.3-chat.html'), 'utf8');
const docs = fs.readFileSync(path.join(repoRoot, 'docs/openbrain-v0.3.md'), 'utf8');
const readme = fs.readFileSync(path.join(repoRoot, 'README.md'), 'utf8');

const requiredSnippets = [
  [ui, `const DEFAULT_ENDPOINT = '${expectedEndpoint}';`, 'UI default endpoint constant'],
  [ui, `const LEGACY_INCOMPLETE_ENDPOINT = '${legacyEndpoint}';`, 'UI legacy endpoint constant'],
  [ui, 'const normalizeEndpointValue = (value) => {', 'UI endpoint normalization helper'],
  [docs, expectedEndpoint, 'v0.3 docs endpoint'],
  [readme, expectedEndpoint, 'README endpoint'],
];

for (const [content, needle, label] of requiredSnippets) {
  if (!content.includes(needle)) {
    console.error(`Missing ${label}: ${needle}`);
    process.exit(1);
  }
}

const normalizeEndpointValue = (value) => {
  const trimmed = typeof value === 'string' ? value.trim() : '';
  if (!trimmed || trimmed === legacyEndpoint) {
    return expectedEndpoint;
  }
  return trimmed;
};

if (normalizeEndpointValue(legacyEndpoint) !== expectedEndpoint) {
  console.error('Legacy incomplete endpoint did not normalize to the assistant endpoint');
  process.exit(1);
}

if (normalizeEndpointValue('http://example.com/custom') !== 'http://example.com/custom') {
  console.error('Custom endpoint would not be preserved');
  process.exit(1);
}

console.log('UI endpoint contract OK');
EOF

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
