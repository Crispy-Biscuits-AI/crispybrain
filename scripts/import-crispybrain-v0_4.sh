#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/Users/elric/repos/crispybrain/scripts/crispybrain-test-harness.sh
source "${SCRIPT_DIR}/crispybrain-test-harness.sh"

SQL_PATH="${REPO_ROOT}/sql/crispybrain-v0_4-upgrade.sql"
WORKFLOW_DIR="${REPO_ROOT}/workflows"
TARGET_FOLDER_NAME="CrispyBrain v0.4"
ASSISTANT_WORKFLOW_ID="assistant"
ASSISTANT_WEBHOOK_PATH="assistant"
ENTRYPOINT_WEBHOOK_URL="http://localhost:5678/webhook/assistant"

openbrain_harness_require_command jq

[[ -f "${SQL_PATH}" ]] || openbrain_harness_fail "SQL file not found: ${SQL_PATH}"
[[ -d "${WORKFLOW_DIR}" ]] || openbrain_harness_fail "Workflow directory not found: ${WORKFLOW_DIR}"

openbrain_harness_apply_sql_file "${SQL_PATH}" "/tmp/crispybrain-v0_4-upgrade.sql" "crispybrain-v0.4 SQL migration"

TARGET_FOLDER_ID="$(openbrain_harness_ensure_folder "${TARGET_FOLDER_NAME}")"
TARGET_FOLDER_ID="$(printf '%s' "${TARGET_FOLDER_ID}" | tr -d '[:space:]')"
[[ -n "${TARGET_FOLDER_ID}" ]] || openbrain_harness_fail "Could not ensure folder ${TARGET_FOLDER_NAME}"
openbrain_harness_log "Using folder ${TARGET_FOLDER_NAME} (${TARGET_FOLDER_ID})"

declare -a imported_workflow_ids=()
TEMP_RENDER_DIR="$(mktemp -d /tmp/crispybrain-import.XXXXXX)"
trap 'rm -rf "${TEMP_RENDER_DIR}"' EXIT

for workflow_path in "${WORKFLOW_DIR}"/*.json; do
  [[ -e "${workflow_path}" ]] || continue
  if ! jq -e '.id and .name and .nodes' "${workflow_path}" >/dev/null 2>&1; then
    openbrain_harness_log "Skipping non-workflow JSON artifact ${workflow_path}"
    continue
  fi

  workflow_id="$(jq -r '.id' "${workflow_path}")"
  workflow_name="$(jq -r '.name' "${workflow_path}")"
  [[ -n "${workflow_id}" && "${workflow_id}" != "null" ]] || openbrain_harness_fail "Workflow id missing in ${workflow_path}"
  [[ "${workflow_name}" == "${workflow_id}" ]] || openbrain_harness_fail "Workflow ${workflow_path} has mismatched name/id: ${workflow_name} vs ${workflow_id}"

  rendered_path="${TEMP_RENDER_DIR}/${workflow_id}.json"
  container_path="/tmp/${workflow_id}.json"
  openbrain_harness_render_workflow_for_folder "${workflow_path}" "${rendered_path}" "${TARGET_FOLDER_ID}" "${TARGET_FOLDER_NAME}"
  openbrain_harness_copy_workflow "${rendered_path}" "${container_path}" "${workflow_name}"
  openbrain_harness_import_workflow "${container_path}" "${workflow_name}"
  imported_workflow_ids+=("${workflow_id}")
done

(( ${#imported_workflow_ids[@]} > 0 )) || openbrain_harness_fail "No importable workflow JSON files were found in ${WORKFLOW_DIR}"

openbrain_harness_log "Listing workflows to confirm imports"
WORKFLOW_LIST_OUTPUT="$(openbrain_harness_list_workflows)"
openbrain_harness_log "${WORKFLOW_LIST_OUTPUT}"

for workflow_id in "${imported_workflow_ids[@]}"; do
  openbrain_harness_assert_workflow_visible "${workflow_id}" "${WORKFLOW_LIST_OUTPUT}"
  openbrain_harness_assert_workflow_in_folder "${workflow_id}" "${TARGET_FOLDER_ID}"
done

openbrain_harness_assert_folder_has_no_legacy_prefixes "${TARGET_FOLDER_ID}"

openbrain_harness_log "Minting local n8n auth cookie"
AUTH_COOKIE="$(openbrain_harness_mint_auth_cookie)"
[[ -n "${AUTH_COOKIE}" ]] || openbrain_harness_fail "Could not mint a local n8n auth cookie"

openbrain_harness_get_json "${OPENBRAIN_HARNESS_REST_BASE_URL}/workflows/${ASSISTANT_WORKFLOW_ID}" -H "Cookie: ${OPENBRAIN_HARNESS_COOKIE_NAME}=${AUTH_COOKIE}"
[[ "${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || openbrain_harness_fail "Could not fetch workflow details for ${ASSISTANT_WORKFLOW_ID}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.data.id' "${ASSISTANT_WORKFLOW_ID}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.data.nodes[] | select(.name == "Assistant Webhook") | .parameters.path' "${ASSISTANT_WEBHOOK_PATH}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.data.parentFolder.name' "${TARGET_FOLDER_NAME}"
WORKFLOW_VERSION_ID="$(openbrain_harness_json_get "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.data.versionId')"
[[ -n "${WORKFLOW_VERSION_ID}" && "${WORKFLOW_VERSION_ID}" != "null" ]] || openbrain_harness_fail "Workflow versionId was missing for ${ASSISTANT_WORKFLOW_ID}"

ACTIVATION_PAYLOAD="$(jq -cn --arg versionId "${WORKFLOW_VERSION_ID}" '{versionId: $versionId}')"
openbrain_harness_activate_workflow "${ASSISTANT_WORKFLOW_ID}" "${AUTH_COOKIE}" "${ACTIVATION_PAYLOAD}"

openbrain_harness_get_json "${OPENBRAIN_HARNESS_REST_BASE_URL}/workflows/${ASSISTANT_WORKFLOW_ID}" -H "Cookie: ${OPENBRAIN_HARNESS_COOKIE_NAME}=${AUTH_COOKIE}"
[[ "${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || openbrain_harness_fail "Could not fetch workflow details for ${ASSISTANT_WORKFLOW_ID} after activation"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.data.active' 'true'
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.data.nodes[] | select(.name == "Assistant Webhook") | .parameters.path' "${ASSISTANT_WEBHOOK_PATH}"
openbrain_harness_assert_json_equals "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" '.data.parentFolder.name' "${TARGET_FOLDER_NAME}"

openbrain_harness_log "Imported workflows:"
printf '%s\n' "${imported_workflow_ids[@]}"

openbrain_harness_pass "CrispyBrain v0.4 workflows imported into ${TARGET_FOLDER_NAME}, verified without legacy openbrain- names, and activated at ${ENTRYPOINT_WEBHOOK_URL}"
