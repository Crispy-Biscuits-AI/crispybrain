#!/usr/bin/env bash

set -euo pipefail

OPENBRAIN_HARNESS_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENBRAIN_HARNESS_N8N_CONTAINER="${OPENBRAIN_HARNESS_N8N_CONTAINER:-ai-n8n}"
OPENBRAIN_HARNESS_DB_CONTAINER="${OPENBRAIN_HARNESS_DB_CONTAINER:-ai-postgres}"
OPENBRAIN_HARNESS_CLI_USER="${OPENBRAIN_HARNESS_CLI_USER:-node}"
OPENBRAIN_HARNESS_COOKIE_NAME="${OPENBRAIN_HARNESS_COOKIE_NAME:-n8n-auth}"
OPENBRAIN_HARNESS_REST_BASE_URL="${OPENBRAIN_HARNESS_REST_BASE_URL:-http://localhost:5678/rest}"
OPENBRAIN_HARNESS_LAST_HTTP_STATUS=""
OPENBRAIN_HARNESS_LAST_HTTP_BODY=""

openbrain_harness_log() {
  printf '%s\n' "$1"
}

openbrain_harness_fail() {
  openbrain_harness_log "FAIL: $1" >&2
  exit 1
}

openbrain_harness_pass() {
  openbrain_harness_log "PASS: $1"
}

openbrain_harness_require_command() {
  command -v "$1" >/dev/null 2>&1 || openbrain_harness_fail "Required command not found: $1"
}

openbrain_harness_copy_workflow() {
  local source_path="$1"
  local container_path="$2"
  local workflow_name="$3"
  openbrain_harness_log "Copying ${workflow_name} into ${OPENBRAIN_HARNESS_N8N_CONTAINER}:${container_path}"
  local output
  output="$(docker cp "${source_path}" "${OPENBRAIN_HARNESS_N8N_CONTAINER}:${container_path}" 2>&1)"
  if [[ -n "${output}" ]]; then
    openbrain_harness_log "${output}"
  fi
}

openbrain_harness_copy_to_container() {
  local source_path="$1"
  local container_name="$2"
  local container_path="$3"
  local label="$4"
  openbrain_harness_log "Copying ${label} into ${container_name}:${container_path}"
  local output
  output="$(docker cp "${source_path}" "${container_name}:${container_path}" 2>&1)"
  if [[ -n "${output}" ]]; then
    openbrain_harness_log "${output}"
  fi
}

openbrain_harness_import_workflow() {
  local container_path="$1"
  local workflow_name="$2"
  openbrain_harness_log "Importing ${workflow_name} into n8n"
  local output
  output="$(docker exec -u "${OPENBRAIN_HARNESS_CLI_USER}" "${OPENBRAIN_HARNESS_N8N_CONTAINER}" n8n import:workflow --input="${container_path}" 2>&1)"
  openbrain_harness_log "${output}"
  grep -Eq 'Successfully imported [0-9]+ workflow|Imported [0-9]+ workflow' <<<"${output}" || openbrain_harness_fail "Workflow import output did not report success for ${workflow_name}"
}

openbrain_harness_list_workflows() {
  docker exec -u "${OPENBRAIN_HARNESS_CLI_USER}" "${OPENBRAIN_HARNESS_N8N_CONTAINER}" n8n list:workflow 2>&1
}

openbrain_harness_assert_workflow_visible() {
  local workflow_name="$1"
  local workflow_list="$2"
  grep -Fq "${workflow_name}" <<<"${workflow_list}" || openbrain_harness_fail "Imported workflow was not found in workflow list: ${workflow_name}"
}

openbrain_harness_mint_auth_cookie() {
  local user_record
  user_record="$(docker exec "${OPENBRAIN_HARNESS_DB_CONTAINER}" psql -U n8n -d n8n -t -A -c "SELECT id || '|' || email || '|' || password || '|' || CASE WHEN \"mfaEnabled\" THEN 't' ELSE 'f' END || '|' || COALESCE(\"mfaSecret\", '') FROM \"user\" LIMIT 1;" 2>&1)"
  [[ -n "${user_record}" ]] || openbrain_harness_fail "Could not read n8n user metadata"

  local user_id user_email user_password_hash user_mfa_enabled user_mfa_secret
  IFS='|' read -r user_id user_email user_password_hash user_mfa_enabled user_mfa_secret <<<"${user_record}"
  [[ -n "${user_id}" && -n "${user_email}" && -n "${user_password_hash}" ]] || openbrain_harness_fail "Incomplete n8n user metadata"

  docker exec -u "${OPENBRAIN_HARNESS_CLI_USER}" "${OPENBRAIN_HARNESS_N8N_CONTAINER}" sh -lc "cd /usr/local/lib/node_modules/n8n && node -e \"const fs=require('fs'); const crypto=require('crypto'); const jwt=require('jsonwebtoken'); const [userId,email,password,mfaEnabled,mfaSecret]=process.argv.slice(1); const config=JSON.parse(fs.readFileSync('/home/node/.n8n/config','utf8')); let jwtSecret=config.userManagement?.jwtSecret || ''; if (!jwtSecret) { let baseKey=''; for (let i=0; i<config.encryptionKey.length; i+=2) baseKey+=config.encryptionKey[i]; jwtSecret=crypto.createHash('sha256').update(baseKey).digest('hex'); } const payload=[email,password]; if (mfaEnabled === 't' && mfaSecret) payload.push(mfaSecret.substring(0, 3)); const hash=crypto.createHash('sha256').update(payload.join(':')).digest('base64').substring(0, 10); const token=jwt.sign({ id:userId, hash, usedMfa:false }, jwtSecret, { expiresIn: 3600 }); process.stdout.write(token);\" '${user_id}' '${user_email}' '${user_password_hash}' '${user_mfa_enabled}' '${user_mfa_secret}'"
}

openbrain_harness_post_json() {
  local url="$1"
  local payload="$2"
  local -a headers=()
  if (( $# > 2 )); then
    headers=("${@:3}")
  fi
  local raw
  if (( ${#headers[@]} > 0 )); then
    raw="$(curl -sS -X POST "${url}" "${headers[@]}" -H 'Content-Type: application/json' --data "${payload}" -w $'\nHTTP_STATUS:%{http_code}' 2>&1)" || {
      openbrain_harness_log "${raw}"
      openbrain_harness_fail "HTTP request failed for ${url}"
    }
  else
    raw="$(curl -sS -X POST "${url}" -H 'Content-Type: application/json' --data "${payload}" -w $'\nHTTP_STATUS:%{http_code}' 2>&1)" || {
      openbrain_harness_log "${raw}"
      openbrain_harness_fail "HTTP request failed for ${url}"
    }
  fi
  OPENBRAIN_HARNESS_LAST_HTTP_STATUS="$(printf '%s\n' "${raw}" | tail -n 1 | sed 's/^HTTP_STATUS://')"
  OPENBRAIN_HARNESS_LAST_HTTP_BODY="$(printf '%s\n' "${raw}" | sed '$d')"
}

openbrain_harness_get_json() {
  local url="$1"
  local -a headers=()
  if (( $# > 1 )); then
    headers=("${@:2}")
  fi
  local raw
  raw="$(curl -sS "${url}" "${headers[@]}" -w $'\nHTTP_STATUS:%{http_code}' 2>&1)" || {
    openbrain_harness_log "${raw}"
    openbrain_harness_fail "HTTP GET failed for ${url}"
  }
  OPENBRAIN_HARNESS_LAST_HTTP_STATUS="$(printf '%s\n' "${raw}" | tail -n 1 | sed 's/^HTTP_STATUS://')"
  OPENBRAIN_HARNESS_LAST_HTTP_BODY="$(printf '%s\n' "${raw}" | sed '$d')"
}

openbrain_harness_register_listener() {
  local workflow_id="$1"
  local destination_node="$2"
  local auth_cookie="$3"
  openbrain_harness_log "Registering webhook-test listener for ${workflow_id}"
  openbrain_harness_post_json \
    "${OPENBRAIN_HARNESS_REST_BASE_URL}/workflows/${workflow_id}/run" \
    "{\"destinationNode\":{\"nodeName\":\"${destination_node}\"}}" \
    -H "Cookie: ${OPENBRAIN_HARNESS_COOKIE_NAME}=${auth_cookie}"
  openbrain_harness_log "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}"
  [[ "${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || openbrain_harness_fail "Unexpected HTTP status while registering ${workflow_id}: ${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}"
  grep -Fq '"waitingForWebhook":true' <<<"${OPENBRAIN_HARNESS_LAST_HTTP_BODY}" || openbrain_harness_fail "n8n did not register webhook-test listener for ${workflow_id}"
}

openbrain_harness_activate_workflow() {
  local workflow_id="$1"
  local auth_cookie="$2"
  local payload="${3-}"
  if [[ -z "${payload}" ]]; then
    payload='{}'
  fi
  openbrain_harness_log "Activating ${workflow_id}"
  openbrain_harness_post_json \
    "${OPENBRAIN_HARNESS_REST_BASE_URL}/workflows/${workflow_id}/activate" \
    "${payload}" \
    -H "Cookie: ${OPENBRAIN_HARNESS_COOKIE_NAME}=${auth_cookie}"
  openbrain_harness_log "${OPENBRAIN_HARNESS_LAST_HTTP_BODY}"
  [[ "${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || openbrain_harness_fail "Unexpected HTTP status while activating ${workflow_id}: ${OPENBRAIN_HARNESS_LAST_HTTP_STATUS}"
}

openbrain_harness_db_query() {
  local sql="$1"
  docker exec "${OPENBRAIN_HARNESS_DB_CONTAINER}" psql -U n8n -d n8n -t -A -c "${sql}"
}

openbrain_harness_apply_sql_file() {
  local source_path="$1"
  local container_path="$2"
  local label="$3"
  openbrain_harness_copy_to_container "${source_path}" "${OPENBRAIN_HARNESS_DB_CONTAINER}" "${container_path}" "${label}"
  openbrain_harness_log "Applying ${label}"
  local output
  output="$(docker exec "${OPENBRAIN_HARNESS_DB_CONTAINER}" psql -U n8n -d n8n -v ON_ERROR_STOP=1 -f "${container_path}" 2>&1)"
  openbrain_harness_log "${output}"
}

openbrain_harness_folder_id_by_name() {
  local folder_name="$1"
  openbrain_harness_db_query "SELECT id FROM folder WHERE name = '${folder_name}' ORDER BY \"createdAt\" ASC LIMIT 1;"
}

openbrain_harness_generate_id() {
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16
}

openbrain_harness_ensure_folder() {
  local folder_name="$1"
  local folder_id
  folder_id="$(openbrain_harness_folder_id_by_name "${folder_name}")"
  folder_id="$(printf '%s' "${folder_id}" | tr -d '[:space:]')"
  if [[ -n "${folder_id}" ]]; then
    printf '%s\n' "${folder_id}"
    return 0
  fi

  local project_id
  project_id="$(openbrain_harness_db_query "SELECT \"projectId\" FROM folder ORDER BY \"createdAt\" ASC LIMIT 1;")"
  project_id="$(printf '%s' "${project_id}" | tr -d '[:space:]')"
  [[ -n "${project_id}" ]] || openbrain_harness_fail "Could not determine the personal project id for folder creation"

  folder_id="$(openbrain_harness_generate_id)"
  openbrain_harness_db_query "INSERT INTO folder (id, name, \"projectId\") VALUES ('${folder_id}', '${folder_name}', '${project_id}');" >/dev/null
  printf '%s\n' "${folder_id}"
}

openbrain_harness_render_workflow_for_folder() {
  local source_path="$1"
  local output_path="$2"
  local folder_id="$3"
  local folder_name="$4"
  jq --arg folderId "${folder_id}" --arg folderName "${folder_name}" '.parentFolder = {id: $folderId, name: $folderName}' "${source_path}" > "${output_path}"
}

openbrain_harness_latest_execution_record() {
  local workflow_id="$1"
  docker exec "${OPENBRAIN_HARNESS_DB_CONTAINER}" psql -U n8n -d n8n -t -A -c "SELECT id::text || '|' || status || '|' || COALESCE(to_char(\"startedAt\", 'YYYY-MM-DD\"T\"HH24:MI:SSOF'), '') FROM execution_entity WHERE \"workflowId\" = '${workflow_id}' ORDER BY \"startedAt\" DESC LIMIT 1;"
}

openbrain_harness_assert_execution_success() {
  local workflow_id="$1"
  local record
  record="$(openbrain_harness_latest_execution_record "${workflow_id}")"
  openbrain_harness_log "${workflow_id}: ${record}"
  [[ -n "${record}" ]] || openbrain_harness_fail "No execution record found for ${workflow_id}"
  grep -Fq '|success|' <<<"${record}" || openbrain_harness_fail "${workflow_id} did not record a success execution"
}

openbrain_harness_json_get() {
  local json_body="$1"
  local jq_expression="$2"
  printf '%s' "${json_body}" | jq -r "${jq_expression}"
}

openbrain_harness_assert_json_equals() {
  local json_body="$1"
  local jq_expression="$2"
  local expected="$3"
  local actual
  actual="$(openbrain_harness_json_get "${json_body}" "${jq_expression}")"
  [[ "${actual}" == "${expected}" ]] || openbrain_harness_fail "Unexpected JSON value for ${jq_expression}: expected '${expected}', got '${actual}'"
}

openbrain_harness_assert_json_number_gt() {
  local json_body="$1"
  local jq_expression="$2"
  local minimum="$3"
  local actual
  actual="$(openbrain_harness_json_get "${json_body}" "${jq_expression}")"
  [[ "${actual}" =~ ^[0-9]+$ ]] || openbrain_harness_fail "Expected numeric JSON value for ${jq_expression}, got '${actual}'"
  (( actual > minimum )) || openbrain_harness_fail "Expected ${jq_expression} > ${minimum}, got ${actual}"
}

openbrain_harness_assert_json_number_gte() {
  local json_body="$1"
  local jq_expression="$2"
  local minimum="$3"
  local actual
  actual="$(openbrain_harness_json_get "${json_body}" "${jq_expression}")"
  [[ "${actual}" =~ ^[0-9]+$ ]] || openbrain_harness_fail "Expected numeric JSON value for ${jq_expression}, got '${actual}'"
  (( actual >= minimum )) || openbrain_harness_fail "Expected ${jq_expression} >= ${minimum}, got ${actual}"
}

openbrain_harness_assert_json_string_contains() {
  local json_body="$1"
  local jq_expression="$2"
  local expected_fragment="$3"
  local actual
  actual="$(openbrain_harness_json_get "${json_body}" "${jq_expression}")"
  grep -Fq "${expected_fragment}" <<<"${actual}" || openbrain_harness_fail "Expected ${jq_expression} to contain '${expected_fragment}', got '${actual}'"
}

openbrain_harness_assert_workflow_in_folder() {
  local workflow_id="$1"
  local folder_id="$2"
  local actual_folder_id
  actual_folder_id="$(openbrain_harness_db_query "SELECT COALESCE(\"parentFolderId\", '') FROM workflow_entity WHERE id = '${workflow_id}' LIMIT 1;")"
  actual_folder_id="$(printf '%s' "${actual_folder_id}" | tr -d '[:space:]')"
  [[ -n "${actual_folder_id}" ]] || openbrain_harness_fail "Workflow ${workflow_id} was not found in workflow_entity"
  [[ "${actual_folder_id}" == "${folder_id}" ]] || openbrain_harness_fail "Workflow ${workflow_id} is in folder '${actual_folder_id}', expected '${folder_id}'"
}

openbrain_harness_assert_folder_has_no_legacy_prefixes() {
  local folder_id="$1"
  local legacy_count
  legacy_count="$(openbrain_harness_db_query "SELECT COUNT(*) FROM workflow_entity WHERE \"parentFolderId\" = '${folder_id}' AND name LIKE 'openbrain-%';")"
  legacy_count="$(printf '%s' "${legacy_count}" | tr -d '[:space:]')"
  [[ "${legacy_count}" == "0" ]] || openbrain_harness_fail "Folder ${folder_id} still contains ${legacy_count} workflow names with the openbrain- prefix"
}

openbrain_harness_list_folder_workflow_names() {
  local folder_id="$1"
  openbrain_harness_db_query "SELECT name FROM workflow_entity WHERE \"parentFolderId\" = '${folder_id}' ORDER BY name;"
}

openbrain_harness_usage() {
  cat <<'EOF'
Reusable CrispyBrain n8n test harness.

Source this file from a workflow-specific test script and call:
  openbrain_harness_copy_workflow
  openbrain_harness_copy_to_container
  openbrain_harness_import_workflow
  openbrain_harness_list_workflows
  openbrain_harness_mint_auth_cookie
  openbrain_harness_activate_workflow
  openbrain_harness_register_listener
  openbrain_harness_post_json
  openbrain_harness_get_json
  openbrain_harness_db_query
  openbrain_harness_apply_sql_file
  openbrain_harness_folder_id_by_name
  openbrain_harness_ensure_folder
  openbrain_harness_render_workflow_for_folder
  openbrain_harness_assert_json_equals
  openbrain_harness_assert_json_number_gt
  openbrain_harness_assert_json_number_gte
  openbrain_harness_assert_json_string_contains
  openbrain_harness_assert_workflow_in_folder
  openbrain_harness_assert_folder_has_no_legacy_prefixes
  openbrain_harness_assert_execution_success
EOF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  openbrain_harness_usage
fi
