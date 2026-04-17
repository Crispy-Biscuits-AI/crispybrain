#!/usr/bin/env bash

set -euo pipefail

CRISPYBRAIN_HARNESS_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRISPYBRAIN_HARNESS_N8N_CONTAINER="${CRISPYBRAIN_HARNESS_N8N_CONTAINER:-ai-n8n}"
CRISPYBRAIN_HARNESS_DB_CONTAINER="${CRISPYBRAIN_HARNESS_DB_CONTAINER:-ai-postgres}"
CRISPYBRAIN_HARNESS_CLI_USER="${CRISPYBRAIN_HARNESS_CLI_USER:-node}"
CRISPYBRAIN_HARNESS_COOKIE_NAME="${CRISPYBRAIN_HARNESS_COOKIE_NAME:-n8n-auth}"
CRISPYBRAIN_HARNESS_REST_BASE_URL="${CRISPYBRAIN_HARNESS_REST_BASE_URL:-http://localhost:5678/rest}"
CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS=""
CRISPYBRAIN_HARNESS_LAST_HTTP_BODY=""

crispybrain_harness_log() {
  printf '%s\n' "$1"
}

crispybrain_harness_fail() {
  crispybrain_harness_log "FAIL: $1" >&2
  exit 1
}

crispybrain_harness_pass() {
  crispybrain_harness_log "PASS: $1"
}

crispybrain_harness_require_command() {
  command -v "$1" >/dev/null 2>&1 || crispybrain_harness_fail "Required command not found: $1"
}

crispybrain_harness_copy_workflow() {
  local source_path="$1"
  local container_path="$2"
  local workflow_name="$3"
  crispybrain_harness_log "Copying ${workflow_name} into ${CRISPYBRAIN_HARNESS_N8N_CONTAINER}:${container_path}"
  local output
  output="$(docker cp "${source_path}" "${CRISPYBRAIN_HARNESS_N8N_CONTAINER}:${container_path}" 2>&1)"
  if [[ -n "${output}" ]]; then
    crispybrain_harness_log "${output}"
  fi
}

crispybrain_harness_copy_to_container() {
  local source_path="$1"
  local container_name="$2"
  local container_path="$3"
  local label="$4"
  crispybrain_harness_log "Copying ${label} into ${container_name}:${container_path}"
  local output
  output="$(docker cp "${source_path}" "${container_name}:${container_path}" 2>&1)"
  if [[ -n "${output}" ]]; then
    crispybrain_harness_log "${output}"
  fi
}

crispybrain_harness_import_workflow() {
  local container_path="$1"
  local workflow_name="$2"
  crispybrain_harness_log "Importing ${workflow_name} into n8n"
  local output
  output="$(docker exec -u "${CRISPYBRAIN_HARNESS_CLI_USER}" "${CRISPYBRAIN_HARNESS_N8N_CONTAINER}" n8n import:workflow --input="${container_path}" 2>&1)"
  crispybrain_harness_log "${output}"
  grep -Eq 'Successfully imported [0-9]+ workflow|Imported [0-9]+ workflow' <<<"${output}" || crispybrain_harness_fail "Workflow import output did not report success for ${workflow_name}"
}

crispybrain_harness_list_workflows() {
  docker exec -u "${CRISPYBRAIN_HARNESS_CLI_USER}" "${CRISPYBRAIN_HARNESS_N8N_CONTAINER}" n8n list:workflow 2>&1
}

crispybrain_harness_assert_workflow_visible() {
  local workflow_name="$1"
  local workflow_list="$2"
  grep -Fq "${workflow_name}" <<<"${workflow_list}" || crispybrain_harness_fail "Imported workflow was not found in workflow list: ${workflow_name}"
}

crispybrain_harness_mint_auth_cookie() {
  local user_record
  user_record="$(docker exec "${CRISPYBRAIN_HARNESS_DB_CONTAINER}" psql -U n8n -d n8n -t -A -c "SELECT id || '|' || email || '|' || password || '|' || CASE WHEN \"mfaEnabled\" THEN 't' ELSE 'f' END || '|' || COALESCE(\"mfaSecret\", '') FROM \"user\" LIMIT 1;" 2>&1)"
  [[ -n "${user_record}" ]] || crispybrain_harness_fail "Could not read n8n user metadata"

  local user_id user_email user_password_hash user_mfa_enabled user_mfa_secret
  IFS='|' read -r user_id user_email user_password_hash user_mfa_enabled user_mfa_secret <<<"${user_record}"
  [[ -n "${user_id}" && -n "${user_email}" && -n "${user_password_hash}" ]] || crispybrain_harness_fail "Incomplete n8n user metadata"

  docker exec -u "${CRISPYBRAIN_HARNESS_CLI_USER}" "${CRISPYBRAIN_HARNESS_N8N_CONTAINER}" sh -lc "cd /usr/local/lib/node_modules/n8n && node -e \"const fs=require('fs'); const crypto=require('crypto'); const jwt=require('jsonwebtoken'); const [userId,email,password,mfaEnabled,mfaSecret]=process.argv.slice(1); const config=JSON.parse(fs.readFileSync('/home/node/.n8n/config','utf8')); let jwtSecret=config.userManagement?.jwtSecret || ''; if (!jwtSecret) { let baseKey=''; for (let i=0; i<config.encryptionKey.length; i+=2) baseKey+=config.encryptionKey[i]; jwtSecret=crypto.createHash('sha256').update(baseKey).digest('hex'); } const payload=[email,password]; if (mfaEnabled === 't' && mfaSecret) payload.push(mfaSecret.substring(0, 3)); const hash=crypto.createHash('sha256').update(payload.join(':')).digest('base64').substring(0, 10); const token=jwt.sign({ id:userId, hash, usedMfa:false }, jwtSecret, { expiresIn: 3600 }); process.stdout.write(token);\" '${user_id}' '${user_email}' '${user_password_hash}' '${user_mfa_enabled}' '${user_mfa_secret}'"
}

crispybrain_harness_post_json() {
  local url="$1"
  local payload="$2"
  local -a headers=()
  if (( $# > 2 )); then
    headers=("${@:3}")
  fi
  local raw
  if (( ${#headers[@]} > 0 )); then
    raw="$(curl -sS -X POST "${url}" "${headers[@]}" -H 'Content-Type: application/json' --data "${payload}" -w $'\nHTTP_STATUS:%{http_code}' 2>&1)" || {
      crispybrain_harness_log "${raw}"
      crispybrain_harness_fail "HTTP request failed for ${url}"
    }
  else
    raw="$(curl -sS -X POST "${url}" -H 'Content-Type: application/json' --data "${payload}" -w $'\nHTTP_STATUS:%{http_code}' 2>&1)" || {
      crispybrain_harness_log "${raw}"
      crispybrain_harness_fail "HTTP request failed for ${url}"
    }
  fi
  CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS="$(printf '%s\n' "${raw}" | tail -n 1 | sed 's/^HTTP_STATUS://')"
  CRISPYBRAIN_HARNESS_LAST_HTTP_BODY="$(printf '%s\n' "${raw}" | sed '$d')"
}

crispybrain_harness_get_json() {
  local url="$1"
  local -a headers=()
  if (( $# > 1 )); then
    headers=("${@:2}")
  fi
  local raw
  raw="$(curl -sS "${url}" "${headers[@]}" -w $'\nHTTP_STATUS:%{http_code}' 2>&1)" || {
    crispybrain_harness_log "${raw}"
    crispybrain_harness_fail "HTTP GET failed for ${url}"
  }
  CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS="$(printf '%s\n' "${raw}" | tail -n 1 | sed 's/^HTTP_STATUS://')"
  CRISPYBRAIN_HARNESS_LAST_HTTP_BODY="$(printf '%s\n' "${raw}" | sed '$d')"
}

crispybrain_harness_register_listener() {
  local workflow_id="$1"
  local destination_node="$2"
  local auth_cookie="$3"
  crispybrain_harness_log "Registering webhook-test listener for ${workflow_id}"
  crispybrain_harness_post_json \
    "${CRISPYBRAIN_HARNESS_REST_BASE_URL}/workflows/${workflow_id}/run" \
    "{\"destinationNode\":{\"nodeName\":\"${destination_node}\"}}" \
    -H "Cookie: ${CRISPYBRAIN_HARNESS_COOKIE_NAME}=${auth_cookie}"
  crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
  [[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Unexpected HTTP status while registering ${workflow_id}: ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
  grep -Fq '"waitingForWebhook":true' <<<"${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}" || crispybrain_harness_fail "n8n did not register webhook-test listener for ${workflow_id}"
}

crispybrain_harness_activate_workflow() {
  local workflow_id="$1"
  local auth_cookie="$2"
  local payload="${3-}"
  if [[ -z "${payload}" ]]; then
    payload='{}'
  fi
  crispybrain_harness_log "Activating ${workflow_id}"
  crispybrain_harness_post_json \
    "${CRISPYBRAIN_HARNESS_REST_BASE_URL}/workflows/${workflow_id}/activate" \
    "${payload}" \
    -H "Cookie: ${CRISPYBRAIN_HARNESS_COOKIE_NAME}=${auth_cookie}"
  crispybrain_harness_log "${CRISPYBRAIN_HARNESS_LAST_HTTP_BODY}"
  [[ "${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}" == "200" ]] || crispybrain_harness_fail "Unexpected HTTP status while activating ${workflow_id}: ${CRISPYBRAIN_HARNESS_LAST_HTTP_STATUS}"
}

crispybrain_harness_db_query() {
  local sql="$1"
  docker exec "${CRISPYBRAIN_HARNESS_DB_CONTAINER}" psql -U n8n -d n8n -t -A -c "${sql}"
}

crispybrain_harness_apply_sql_file() {
  local source_path="$1"
  local container_path="$2"
  local label="$3"
  crispybrain_harness_copy_to_container "${source_path}" "${CRISPYBRAIN_HARNESS_DB_CONTAINER}" "${container_path}" "${label}"
  crispybrain_harness_log "Applying ${label}"
  local output
  output="$(docker exec "${CRISPYBRAIN_HARNESS_DB_CONTAINER}" psql -U n8n -d n8n -v ON_ERROR_STOP=1 -f "${container_path}" 2>&1)"
  crispybrain_harness_log "${output}"
}

crispybrain_harness_folder_id_by_name() {
  local folder_name="$1"
  crispybrain_harness_db_query "SELECT id FROM folder WHERE name = '${folder_name}' ORDER BY \"createdAt\" ASC LIMIT 1;"
}

crispybrain_harness_generate_id() {
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16
}

crispybrain_harness_ensure_folder() {
  local folder_name="$1"
  local folder_id
  folder_id="$(crispybrain_harness_folder_id_by_name "${folder_name}")"
  folder_id="$(printf '%s' "${folder_id}" | tr -d '[:space:]')"
  if [[ -n "${folder_id}" ]]; then
    printf '%s\n' "${folder_id}"
    return 0
  fi

  local project_id
  project_id="$(crispybrain_harness_db_query "SELECT \"projectId\" FROM folder ORDER BY \"createdAt\" ASC LIMIT 1;")"
  project_id="$(printf '%s' "${project_id}" | tr -d '[:space:]')"
  [[ -n "${project_id}" ]] || crispybrain_harness_fail "Could not determine the personal project id for folder creation"

  folder_id="$(crispybrain_harness_generate_id)"
  crispybrain_harness_db_query "INSERT INTO folder (id, name, \"projectId\") VALUES ('${folder_id}', '${folder_name}', '${project_id}');" >/dev/null
  printf '%s\n' "${folder_id}"
}

crispybrain_harness_render_workflow_for_folder() {
  local source_path="$1"
  local output_path="$2"
  local folder_id="$3"
  local folder_name="$4"
  jq --arg folderId "${folder_id}" --arg folderName "${folder_name}" '.parentFolder = {id: $folderId, name: $folderName}' "${source_path}" > "${output_path}"
}

crispybrain_harness_latest_execution_record() {
  local workflow_id="$1"
  docker exec "${CRISPYBRAIN_HARNESS_DB_CONTAINER}" psql -U n8n -d n8n -t -A -c "SELECT id::text || '|' || status || '|' || COALESCE(to_char(\"startedAt\", 'YYYY-MM-DD\"T\"HH24:MI:SSOF'), '') FROM execution_entity WHERE \"workflowId\" = '${workflow_id}' ORDER BY \"startedAt\" DESC LIMIT 1;"
}

crispybrain_harness_assert_execution_success() {
  local workflow_id="$1"
  local record
  record="$(crispybrain_harness_latest_execution_record "${workflow_id}")"
  crispybrain_harness_log "${workflow_id}: ${record}"
  [[ -n "${record}" ]] || crispybrain_harness_fail "No execution record found for ${workflow_id}"
  grep -Fq '|success|' <<<"${record}" || crispybrain_harness_fail "${workflow_id} did not record a success execution"
}

crispybrain_harness_json_get() {
  local json_body="$1"
  local jq_expression="$2"
  printf '%s' "${json_body}" | jq -r "${jq_expression}"
}

crispybrain_harness_assert_json_equals() {
  local json_body="$1"
  local jq_expression="$2"
  local expected="$3"
  local actual
  actual="$(crispybrain_harness_json_get "${json_body}" "${jq_expression}")"
  [[ "${actual}" == "${expected}" ]] || crispybrain_harness_fail "Unexpected JSON value for ${jq_expression}: expected '${expected}', got '${actual}'"
}

crispybrain_harness_assert_json_number_gt() {
  local json_body="$1"
  local jq_expression="$2"
  local minimum="$3"
  local actual
  actual="$(crispybrain_harness_json_get "${json_body}" "${jq_expression}")"
  [[ "${actual}" =~ ^[0-9]+$ ]] || crispybrain_harness_fail "Expected numeric JSON value for ${jq_expression}, got '${actual}'"
  (( actual > minimum )) || crispybrain_harness_fail "Expected ${jq_expression} > ${minimum}, got ${actual}"
}

crispybrain_harness_assert_json_number_gte() {
  local json_body="$1"
  local jq_expression="$2"
  local minimum="$3"
  local actual
  actual="$(crispybrain_harness_json_get "${json_body}" "${jq_expression}")"
  [[ "${actual}" =~ ^[0-9]+$ ]] || crispybrain_harness_fail "Expected numeric JSON value for ${jq_expression}, got '${actual}'"
  (( actual >= minimum )) || crispybrain_harness_fail "Expected ${jq_expression} >= ${minimum}, got ${actual}"
}

crispybrain_harness_assert_json_string_contains() {
  local json_body="$1"
  local jq_expression="$2"
  local expected_fragment="$3"
  local actual
  actual="$(crispybrain_harness_json_get "${json_body}" "${jq_expression}")"
  grep -Fq "${expected_fragment}" <<<"${actual}" || crispybrain_harness_fail "Expected ${jq_expression} to contain '${expected_fragment}', got '${actual}'"
}

crispybrain_harness_assert_workflow_in_folder() {
  local workflow_id="$1"
  local folder_id="$2"
  local actual_folder_id
  actual_folder_id="$(crispybrain_harness_db_query "SELECT COALESCE(\"parentFolderId\", '') FROM workflow_entity WHERE id = '${workflow_id}' LIMIT 1;")"
  actual_folder_id="$(printf '%s' "${actual_folder_id}" | tr -d '[:space:]')"
  [[ -n "${actual_folder_id}" ]] || crispybrain_harness_fail "Workflow ${workflow_id} was not found in workflow_entity"
  [[ "${actual_folder_id}" == "${folder_id}" ]] || crispybrain_harness_fail "Workflow ${workflow_id} is in folder '${actual_folder_id}', expected '${folder_id}'"
}

crispybrain_harness_assert_folder_has_no_legacy_prefixes() {
  local folder_id="$1"
  local legacy_count
  legacy_count="$(crispybrain_harness_db_query "SELECT COUNT(*) FROM workflow_entity WHERE \"parentFolderId\" = '${folder_id}' AND name LIKE 'openbrain-%';")"
  legacy_count="$(printf '%s' "${legacy_count}" | tr -d '[:space:]')"
  [[ "${legacy_count}" == "0" ]] || crispybrain_harness_fail "Folder ${folder_id} still contains ${legacy_count} workflow names with the legacy prefix"
}

crispybrain_harness_list_folder_workflow_names() {
  local folder_id="$1"
  crispybrain_harness_db_query "SELECT name FROM workflow_entity WHERE \"parentFolderId\" = '${folder_id}' ORDER BY name;"
}

crispybrain_harness_usage() {
  cat <<'EOF'
Reusable CrispyBrain n8n test harness.

Source this file from a workflow-specific test script and call:
  crispybrain_harness_copy_workflow
  crispybrain_harness_copy_to_container
  crispybrain_harness_import_workflow
  crispybrain_harness_list_workflows
  crispybrain_harness_mint_auth_cookie
  crispybrain_harness_activate_workflow
  crispybrain_harness_register_listener
  crispybrain_harness_post_json
  crispybrain_harness_get_json
  crispybrain_harness_db_query
  crispybrain_harness_apply_sql_file
  crispybrain_harness_folder_id_by_name
  crispybrain_harness_ensure_folder
  crispybrain_harness_render_workflow_for_folder
  crispybrain_harness_assert_json_equals
  crispybrain_harness_assert_json_number_gt
  crispybrain_harness_assert_json_number_gte
  crispybrain_harness_assert_json_string_contains
  crispybrain_harness_assert_workflow_in_folder
  crispybrain_harness_assert_folder_has_no_legacy_prefixes
  crispybrain_harness_assert_execution_success
EOF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  crispybrain_harness_usage
fi
