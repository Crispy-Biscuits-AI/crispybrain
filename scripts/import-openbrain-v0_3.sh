#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/Users/elric/repos/openbrain/scripts/openbrain-test-harness.sh
source "${SCRIPT_DIR}/openbrain-test-harness.sh"

SQL_PATH="${REPO_ROOT}/sql/openbrain-v0_3-upgrade.sql"
WORKFLOW_PATH="${REPO_ROOT}/workflows/openbrain-assistant.json"

SQL_CONTAINER_PATH="/tmp/openbrain-v0_3-upgrade.sql"
WORKFLOW_CONTAINER_PATH="/tmp/openbrain-assistant.json"

WORKFLOW_NAME="openbrain-assistant"
WORKFLOW_ID="openbrain-assistant"
TARGET_FOLDER_NAME="OpenBrain v0.3"
ENTRYPOINT_WEBHOOK_URL="http://localhost:5678/webhook/openbrain-assistant"

[[ -f "${SQL_PATH}" ]] || openbrain_harness_fail "SQL file not found: ${SQL_PATH}"
[[ -f "${WORKFLOW_PATH}" ]] || openbrain_harness_fail "Workflow file not found: ${WORKFLOW_PATH}"

openbrain_harness_apply_sql_file "${SQL_PATH}" "${SQL_CONTAINER_PATH}" "openbrain-v0.3 SQL migration"

openbrain_harness_copy_workflow "${WORKFLOW_PATH}" "${WORKFLOW_CONTAINER_PATH}" "${WORKFLOW_NAME}"
openbrain_harness_import_workflow "${WORKFLOW_CONTAINER_PATH}" "${WORKFLOW_NAME}"

openbrain_harness_log "Listing workflows to confirm import"
WORKFLOW_LIST_OUTPUT="$(openbrain_harness_list_workflows)"
openbrain_harness_log "${WORKFLOW_LIST_OUTPUT}"
openbrain_harness_assert_workflow_visible "${WORKFLOW_NAME}" "${WORKFLOW_LIST_OUTPUT}"

openbrain_harness_log "Minting local n8n auth cookie"
AUTH_COOKIE="$(openbrain_harness_mint_auth_cookie)"
[[ -n "${AUTH_COOKIE}" ]] || openbrain_harness_fail "Could not mint a local n8n auth cookie"

openbrain_harness_get_json "${OPENBRAIN_HARNESS_REST_BASE_URL}/workflows/${WORKFLOW_ID}" -H "Cookie: ${OPENBRAIN_HARNESS_COOKIE_NAME}=${AUTH_COOKIE}"
[[ "${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || openbrain_harness_fail "Could not fetch workflow details for ${WORKFLOW_ID}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.data.id' "${WORKFLOW_ID}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.data.nodes[] | select(.name == "Assistant Webhook") | .parameters.path' "${WORKFLOW_ID}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.data.parentFolder.name' "${TARGET_FOLDER_NAME}"
WORKFLOW_VERSION_ID="$(openbrain_harness_json_get "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.data.versionId')"
[[ -n "${WORKFLOW_VERSION_ID}" && "${WORKFLOW_VERSION_ID}" != "null" ]] || openbrain_harness_fail "Workflow versionId was missing for ${WORKFLOW_ID}"
ACTIVATION_PAYLOAD="$(jq -cn --arg versionId "${WORKFLOW_VERSION_ID}" '{versionId: $versionId}')"

openbrain_harness_activate_workflow "${WORKFLOW_ID}" "${AUTH_COOKIE}" "${ACTIVATION_PAYLOAD}"
openbrain_harness_get_json "${OPENBRAIN_HARNESS_REST_BASE_URL}/workflows/${WORKFLOW_ID}" -H "Cookie: ${OPENBRAIN_HARNESS_COOKIE_NAME}=${AUTH_COOKIE}"
[[ "${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || openbrain_harness_fail "Could not fetch workflow details for ${WORKFLOW_ID} after activation"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.data.active' 'true'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.data.nodes[] | select(.name == "Assistant Webhook") | .parameters.path' "${WORKFLOW_ID}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.data.parentFolder.name' "${TARGET_FOLDER_NAME}"

openbrain_harness_pass "OpenBrain v0.3 assistant imported, verified in folder ${TARGET_FOLDER_NAME}, verified at webhook path ${WORKFLOW_ID}, and activated at ${ENTRYPOINT_WEBHOOK_URL}"
