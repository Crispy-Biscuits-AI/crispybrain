#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/Users/elric/repos/openbrain/scripts/openbrain-test-harness.sh
source "${SCRIPT_DIR}/openbrain-test-harness.sh"

WORKFLOW_VALIDATION_PATH="${REPO_ROOT}/workflows/openbrain-validation-and-errors.json"
WORKFLOW_PROJECT_MEMORY_PATH="${REPO_ROOT}/workflows/openbrain-project-memory.json"
WORKFLOW_AUTO_INGEST_PATH="${REPO_ROOT}/workflows/openbrain-auto-ingest-watch.json"

CONTAINER_VALIDATION_PATH="/tmp/openbrain-validation-and-errors.json"
CONTAINER_PROJECT_MEMORY_PATH="/tmp/openbrain-project-memory.json"
CONTAINER_AUTO_INGEST_PATH="/tmp/openbrain-auto-ingest-watch.json"

VALIDATION_WORKFLOW_NAME="openbrain-validation-and-errors"
PROJECT_MEMORY_WORKFLOW_NAME="openbrain-project-memory"
AUTO_INGEST_WORKFLOW_NAME="openbrain-auto-ingest-watch"

VALIDATION_WORKFLOW_ID="openbrain-validation-and-errors"
PROJECT_MEMORY_WORKFLOW_ID="openbrain-project-memory"
AUTO_INGEST_WORKFLOW_ID="openbrain-auto-ingest-watch"

VALIDATION_DESTINATION_NODE="Respond Validation Result"
PROJECT_MEMORY_DESTINATION_NODE="Respond Project Memory Result"
AUTO_INGEST_DESTINATION_NODE="Respond Auto Ingest Result"

VALIDATION_WEBHOOK_TEST_URL="http://localhost:5678/webhook-test/openbrain-validation-and-errors"
PROJECT_MEMORY_WEBHOOK_TEST_URL="http://localhost:5678/webhook-test/openbrain-project-memory"
AUTO_INGEST_WEBHOOK_TEST_URL="http://localhost:5678/webhook-test/openbrain-auto-ingest-watch"

openbrain_harness_require_command jq
openbrain_harness_require_command curl

[[ -f "${WORKFLOW_VALIDATION_PATH}" ]] || openbrain_harness_fail "Workflow file not found: ${WORKFLOW_VALIDATION_PATH}"
[[ -f "${WORKFLOW_PROJECT_MEMORY_PATH}" ]] || openbrain_harness_fail "Workflow file not found: ${WORKFLOW_PROJECT_MEMORY_PATH}"
[[ -f "${WORKFLOW_AUTO_INGEST_PATH}" ]] || openbrain_harness_fail "Workflow file not found: ${WORKFLOW_AUTO_INGEST_PATH}"

openbrain_harness_copy_workflow "${WORKFLOW_VALIDATION_PATH}" "${CONTAINER_VALIDATION_PATH}" "${VALIDATION_WORKFLOW_NAME}"
openbrain_harness_copy_workflow "${WORKFLOW_PROJECT_MEMORY_PATH}" "${CONTAINER_PROJECT_MEMORY_PATH}" "${PROJECT_MEMORY_WORKFLOW_NAME}"
openbrain_harness_copy_workflow "${WORKFLOW_AUTO_INGEST_PATH}" "${CONTAINER_AUTO_INGEST_PATH}" "${AUTO_INGEST_WORKFLOW_NAME}"

openbrain_harness_import_workflow "${CONTAINER_VALIDATION_PATH}" "${VALIDATION_WORKFLOW_NAME}"
openbrain_harness_import_workflow "${CONTAINER_PROJECT_MEMORY_PATH}" "${PROJECT_MEMORY_WORKFLOW_NAME}"
openbrain_harness_import_workflow "${CONTAINER_AUTO_INGEST_PATH}" "${AUTO_INGEST_WORKFLOW_NAME}"

openbrain_harness_log "Listing workflows to confirm imports"
WORKFLOW_LIST_OUTPUT="$(openbrain_harness_list_workflows)"
openbrain_harness_log "${WORKFLOW_LIST_OUTPUT}"
openbrain_harness_assert_workflow_visible "${VALIDATION_WORKFLOW_NAME}" "${WORKFLOW_LIST_OUTPUT}"
openbrain_harness_assert_workflow_visible "${PROJECT_MEMORY_WORKFLOW_NAME}" "${WORKFLOW_LIST_OUTPUT}"
openbrain_harness_assert_workflow_visible "${AUTO_INGEST_WORKFLOW_NAME}" "${WORKFLOW_LIST_OUTPUT}"

openbrain_harness_log "Minting local n8n auth cookie"
AUTH_COOKIE="$(openbrain_harness_mint_auth_cookie)"
[[ -n "${AUTH_COOKIE}" ]] || openbrain_harness_fail "Could not mint a local n8n auth cookie"

openbrain_harness_register_listener "${VALIDATION_WORKFLOW_ID}" "${VALIDATION_DESTINATION_NODE}" "${AUTH_COOKIE}"
openbrain_harness_log "Executing ${VALIDATION_WORKFLOW_NAME} success case"
openbrain_harness_post_json "${VALIDATION_WEBHOOK_TEST_URL}" '{"query":"test","project_slug":"alpha"}'
openbrain_harness_log "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}"
[[ "${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || openbrain_harness_fail "Unexpected HTTP status from ${VALIDATION_WORKFLOW_NAME} success case: ${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.ok' 'true'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.message' 'Validation passed'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.query' 'test'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.project_slug' 'alpha'

openbrain_harness_register_listener "${VALIDATION_WORKFLOW_ID}" "${VALIDATION_DESTINATION_NODE}" "${AUTH_COOKIE}"
openbrain_harness_log "Executing ${VALIDATION_WORKFLOW_NAME} failure case"
openbrain_harness_post_json "${VALIDATION_WEBHOOK_TEST_URL}" '{"query":""}'
openbrain_harness_log "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}"
[[ "${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || openbrain_harness_fail "Unexpected HTTP status from ${VALIDATION_WORKFLOW_NAME} failure case: ${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.ok' 'false'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.error' 'Missing or invalid query'

openbrain_harness_register_listener "${PROJECT_MEMORY_WORKFLOW_ID}" "${PROJECT_MEMORY_DESTINATION_NODE}" "${AUTH_COOKIE}"
openbrain_harness_log "Executing ${PROJECT_MEMORY_WORKFLOW_NAME}"
openbrain_harness_post_json "${PROJECT_MEMORY_WEBHOOK_TEST_URL}" '{"query":"How am I planning to build OpenBrain?","project_slug":"alpha"}'
openbrain_harness_log "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}"
[[ "${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || openbrain_harness_fail "Unexpected HTTP status from ${PROJECT_MEMORY_WORKFLOW_NAME}: ${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.ok' 'true'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.project_slug' 'alpha'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.memory_filter.project_slug' 'alpha'

openbrain_harness_register_listener "${AUTO_INGEST_WORKFLOW_ID}" "${AUTO_INGEST_DESTINATION_NODE}" "${AUTH_COOKIE}"
openbrain_harness_log "Executing ${AUTO_INGEST_WORKFLOW_NAME}"
openbrain_harness_post_json "${AUTO_INGEST_WEBHOOK_TEST_URL}" '{"filepath":"/tmp/example.txt","filename":"example.txt","project_slug":"alpha"}'
openbrain_harness_log "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}"
[[ "${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || openbrain_harness_fail "Unexpected HTTP status from ${AUTO_INGEST_WORKFLOW_NAME}: ${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.ok' 'true'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.filepath' '/tmp/example.txt'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.filename' 'example.txt'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.project_slug' 'alpha'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.next_workflow' 'openbrain-ingest'

openbrain_harness_log "Checking n8n execution records"
openbrain_harness_assert_execution_success "${VALIDATION_WORKFLOW_ID}"
openbrain_harness_assert_execution_success "${PROJECT_MEMORY_WORKFLOW_ID}"
openbrain_harness_assert_execution_success "${AUTO_INGEST_WORKFLOW_ID}"

openbrain_harness_pass "All remaining v0.2 workflows imported, executed in webhook-test mode, and recorded successful n8n executions"
