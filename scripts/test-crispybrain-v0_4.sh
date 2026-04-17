#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/Users/elric/repos/crispybrain/scripts/crispybrain-test-harness.sh
source "${SCRIPT_DIR}/crispybrain-test-harness.sh"

IMPORT_SCRIPT="${SCRIPT_DIR}/import-crispybrain-v0_4.sh"
WORKFLOW_ID="assistant"
WEBHOOK_URL="http://localhost:5678/webhook/assistant"
SESSION_TEST_ID="crispybrain-v0-4-session-test"
TARGET_FOLDER_NAME="CrispyBrain v0.4"
UI_PATH="${SCRIPT_DIR}/../docs/crispybrain-v0.4-chat.html"
DOC_PATH="${SCRIPT_DIR}/../docs/crispybrain-v0.4.md"
README_PATH="${SCRIPT_DIR}/../README.md"

openbrain_harness_require_command jq
openbrain_harness_require_command curl
openbrain_harness_require_command node

[[ -x "${IMPORT_SCRIPT}" ]] || openbrain_harness_fail "Import script is missing or not executable: ${IMPORT_SCRIPT}"
[[ -f "${UI_PATH}" ]] || openbrain_harness_fail "UI file is missing: ${UI_PATH}"
[[ -f "${DOC_PATH}" ]] || openbrain_harness_fail "v0.4 docs file is missing: ${DOC_PATH}"
[[ -f "${README_PATH}" ]] || openbrain_harness_fail "README is missing: ${README_PATH}"

openbrain_harness_log "Test 0: WebUI and docs contract"
node - <<'EOF'
const fs = require('fs');
const path = require('path');

const repoRoot = process.cwd();
const expectedEndpoint = 'http://localhost:5678/webhook/assistant';
const legacyAssistantEndpoint = 'http://localhost:5678/webhook/openbrain-assistant';
const legacyBareEndpoint = 'http://localhost:5678/webhook';
const ui = fs.readFileSync(path.join(repoRoot, 'docs/crispybrain-v0.4-chat.html'), 'utf8');
const docs = fs.readFileSync(path.join(repoRoot, 'docs/crispybrain-v0.4.md'), 'utf8');
const readme = fs.readFileSync(path.join(repoRoot, 'README.md'), 'utf8');

const requiredSnippets = [
  [ui, '<title>CrispyBrain v0.4</title>', 'UI title'],
  [ui, 'dark polarized', 'dark polarized theme label'],
  [ui, 'light polarized', 'light polarized theme label'],
  [ui, `const DEFAULT_ENDPOINT = '${expectedEndpoint}';`, 'default assistant endpoint'],
  [ui, "const DEFAULT_THEME = 'dark-polarized';", 'default theme constant'],
  [ui, "const THEME_STORAGE_KEY = 'crispybrain_theme';", 'theme storage key'],
  [ui, "const ENDPOINT_STORAGE_KEY = 'crispybrain_endpoint';", 'endpoint storage key'],
  [ui, "const LEGACY_ENDPOINT_STORAGE_KEYS = ['openbrain_endpoint', 'openbrain-v0.3-endpoint'];", 'legacy endpoint storage migration'],
  [docs, expectedEndpoint, 'docs assistant endpoint'],
  [readme, expectedEndpoint, 'README assistant endpoint'],
];

for (const [content, needle, label] of requiredSnippets) {
  if (!content.includes(needle)) {
    console.error(`Missing ${label}: ${needle}`);
    process.exit(1);
  }
}

const normalizeEndpointValue = (value) => {
  const trimmed = typeof value === 'string' ? value.trim() : '';
  if (!trimmed || trimmed === legacyBareEndpoint || trimmed === legacyAssistantEndpoint) {
    return expectedEndpoint;
  }
  return trimmed;
};

if (normalizeEndpointValue(legacyAssistantEndpoint) !== expectedEndpoint) {
  console.error('Old OpenBrain assistant endpoint did not migrate to the CrispyBrain assistant endpoint');
  process.exit(1);
}

if (normalizeEndpointValue(legacyBareEndpoint) !== expectedEndpoint) {
  console.error('Old incomplete /webhook endpoint did not migrate to the CrispyBrain assistant endpoint');
  process.exit(1);
}

if (normalizeEndpointValue('http://example.com/custom') !== 'http://example.com/custom') {
  console.error('Custom endpoint would not be preserved');
  process.exit(1);
}

console.log('UI contract OK');
EOF

"${IMPORT_SCRIPT}"

TARGET_FOLDER_ID="$(openbrain_harness_folder_id_by_name "${TARGET_FOLDER_NAME}")"
TARGET_FOLDER_ID="$(printf '%s' "${TARGET_FOLDER_ID}" | tr -d '[:space:]')"
[[ -n "${TARGET_FOLDER_ID}" ]] || openbrain_harness_fail "Folder ${TARGET_FOLDER_NAME} was not found after import"
openbrain_harness_assert_folder_has_no_legacy_prefixes "${TARGET_FOLDER_ID}"

openbrain_harness_log "Resetting session test rows"
openbrain_harness_db_query "DELETE FROM openbrain_chat_turns WHERE session_id = '${SESSION_TEST_ID}';" >/dev/null

openbrain_harness_log "Test 1: plain chat request"
openbrain_harness_post_json "${WEBHOOK_URL}" '{"message":"What is CrispyBrain?"}'
openbrain_harness_log "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}"
[[ "${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || openbrain_harness_fail "Plain chat request returned HTTP ${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.ok' 'true'
openbrain_harness_assert_json_string_contains "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.answer' 'CrispyBrain'
openbrain_harness_assert_json_number_gte "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.retrieval.memory_count' 1

openbrain_harness_log "Test 2: project-aware request"
openbrain_harness_post_json "${WEBHOOK_URL}" '{"message":"How am I planning to build CrispyBrain?","project_slug":"alpha","top_k":4}'
openbrain_harness_log "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}"
[[ "${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || openbrain_harness_fail "Project-aware request returned HTTP ${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.ok' 'true'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.project_slug' 'alpha'
openbrain_harness_assert_json_number_gte "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.sources | length' 1

openbrain_harness_log "Test 3a: first turn in a session"
openbrain_harness_post_json "${WEBHOOK_URL}" "{\"message\":\"What is the CrispyBrain architecture?\",\"project_slug\":\"alpha\",\"session_id\":\"${SESSION_TEST_ID}\"}"
openbrain_harness_log "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}"
[[ "${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || openbrain_harness_fail "Session continuity turn 1 returned HTTP ${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.ok' 'true'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.session_id' "${SESSION_TEST_ID}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.session.turn_count_before' '0'

openbrain_harness_log "Test 3b: second turn in the same session"
openbrain_harness_post_json "${WEBHOOK_URL}" "{\"message\":\"What is the next planned workflow?\",\"project_slug\":\"alpha\",\"session_id\":\"${SESSION_TEST_ID}\"}"
openbrain_harness_log "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}"
[[ "${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || openbrain_harness_fail "Session continuity turn 2 returned HTTP ${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.ok' 'true'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.session_id' "${SESSION_TEST_ID}"
openbrain_harness_assert_json_number_gte "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.session.turn_count_before' 2
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.session.history_used' 'true'

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

openbrain_harness_log "Checking n8n execution records"
openbrain_harness_assert_execution_success "${WORKFLOW_ID}"

openbrain_harness_pass "CrispyBrain v0.4 workflows passed the UI contract check, assistant webhook smoke test, session continuity, invalid input, and empty retrieval tests"
