#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONTAINER_NAME="ai-n8n"
DB_CONTAINER_NAME="ai-postgres"
CLI_USER="node"
COOKIE_NAME="n8n-auth"
REST_BASE_URL="http://localhost:5678/rest"
BUILD_WORKFLOW_PATH="${REPO_ROOT}/workflows/build-context.json"
ANSWER_WORKFLOW_PATH="${REPO_ROOT}/workflows/answer-from-memory.json"
BUILD_CONTAINER_PATH="/tmp/build-context.json"
ANSWER_CONTAINER_PATH="/tmp/answer-from-memory.json"
BUILD_WORKFLOW_NAME="build-context"
ANSWER_WORKFLOW_NAME="answer-from-memory"
BUILD_WORKFLOW_ID="build-context"
ANSWER_WORKFLOW_ID="answer-from-memory"
BUILD_DESTINATION_NODE="Respond Build Context"
ANSWER_DESTINATION_NODE="Respond Answer From Memory"
BUILD_WEBHOOK_TEST_URL="http://localhost:5678/webhook-test/build-context"
ANSWER_WEBHOOK_TEST_URL="http://localhost:5678/webhook-test/answer-from-memory"
QUERY_TEXT="What am I planning to build?"

LAST_HTTP_STATUS=""
LAST_HTTP_BODY=""

print_log() {
  printf '%s\n' "$1"
}

fail() {
  print_log "FAIL: $1" >&2
  exit 1
}

pass() {
  print_log "PASS: $1"
  exit 0
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

copy_workflow() {
  local source_path="$1"
  local container_path="$2"
  local workflow_name="$3"
  print_log "Copying ${workflow_name} into ${CONTAINER_NAME}:${container_path}"
  local output
  output="$(docker cp "${source_path}" "${CONTAINER_NAME}:${container_path}" 2>&1)"
  if [[ -n "${output}" ]]; then
    print_log "${output}"
  fi
}

import_workflow() {
  local container_path="$1"
  local workflow_name="$2"
  print_log "Importing ${workflow_name} into n8n"
  local output
  output="$(docker exec -u "${CLI_USER}" "${CONTAINER_NAME}" n8n import:workflow --input="${container_path}" 2>&1)"
  print_log "${output}"
  if ! grep -Eq 'Successfully imported [0-9]+ workflow|Imported [0-9]+ workflow' <<<"${output}"; then
    fail "Workflow import output did not report success for ${workflow_name}"
  fi
}

assert_workflow_visible() {
  local workflow_name="$1"
  if ! grep -Fq "${workflow_name}" <<<"${WORKFLOW_LIST_OUTPUT}"; then
    fail "Imported workflow was not found in workflow list: ${workflow_name}"
  fi
}

mint_auth_cookie() {
  local user_record
  user_record="$(docker exec "${DB_CONTAINER_NAME}" psql -U n8n -d n8n -t -A -c "SELECT id || '|' || email || '|' || password || '|' || CASE WHEN \"mfaEnabled\" THEN 't' ELSE 'f' END || '|' || COALESCE(\"mfaSecret\", '') FROM \"user\" LIMIT 1;" 2>&1)"
  [[ -n "${user_record}" ]] || fail "Could not read n8n user metadata"

  local user_id user_email user_password_hash user_mfa_enabled user_mfa_secret
  IFS='|' read -r user_id user_email user_password_hash user_mfa_enabled user_mfa_secret <<<"${user_record}"

  [[ -n "${user_id}" && -n "${user_email}" && -n "${user_password_hash}" ]] || fail "Incomplete n8n user metadata"

  docker exec -u "${CLI_USER}" "${CONTAINER_NAME}" sh -lc "cd /usr/local/lib/node_modules/n8n && node -e \"const fs=require('fs'); const crypto=require('crypto'); const jwt=require('jsonwebtoken'); const [userId,email,password,mfaEnabled,mfaSecret]=process.argv.slice(1); const config=JSON.parse(fs.readFileSync('/home/node/.n8n/config','utf8')); let jwtSecret=config.userManagement?.jwtSecret || ''; if (!jwtSecret) { let baseKey=''; for (let i=0; i<config.encryptionKey.length; i+=2) baseKey+=config.encryptionKey[i]; jwtSecret=crypto.createHash('sha256').update(baseKey).digest('hex'); } const payload=[email,password]; if (mfaEnabled === 't' && mfaSecret) payload.push(mfaSecret.substring(0, 3)); const hash=crypto.createHash('sha256').update(payload.join(':')).digest('base64').substring(0, 10); const token=jwt.sign({ id:userId, hash, usedMfa:false }, jwtSecret, { expiresIn: 3600 }); process.stdout.write(token);\" '${user_id}' '${user_email}' '${user_password_hash}' '${user_mfa_enabled}' '${user_mfa_secret}'"
}

post_json() {
  local url="$1"
  local payload="$2"
  local -a headers=()
  if (( $# > 2 )); then
    headers=("${@:3}")
  fi
  local raw
  if (( ${#headers[@]} > 0 )); then
    raw="$(curl -sS -X POST "${url}" "${headers[@]}" -H 'Content-Type: application/json' --data "${payload}" -w $'\nHTTP_STATUS:%{http_code}' 2>&1)" || {
      print_log "${raw}"
      fail "HTTP request failed for ${url}"
    }
  else
    raw="$(curl -sS -X POST "${url}" -H 'Content-Type: application/json' --data "${payload}" -w $'\nHTTP_STATUS:%{http_code}' 2>&1)" || {
      print_log "${raw}"
      fail "HTTP request failed for ${url}"
    }
  fi
  LAST_HTTP_STATUS="$(printf '%s\n' "${raw}" | tail -n 1 | sed 's/^HTTP_STATUS://')"
  LAST_HTTP_BODY="$(printf '%s\n' "${raw}" | sed '$d')"
}

register_listener() {
  local workflow_id="$1"
  local destination_node="$2"
  local auth_cookie="$3"
  print_log "Registering webhook-test listener for ${workflow_id}"
  post_json \
    "${REST_BASE_URL}/workflows/${workflow_id}/run" \
    "{\"destinationNode\":{\"nodeName\":\"${destination_node}\"}}" \
    -H "Cookie: ${COOKIE_NAME}=${auth_cookie}"
  print_log "${LAST_HTTP_BODY}"
  [[ "${LAST_HTTP_STATUS}" == "200" ]] || fail "Unexpected HTTP status while registering ${workflow_id}: ${LAST_HTTP_STATUS}"
  grep -Fq '"waitingForWebhook":true' <<<"${LAST_HTTP_BODY}" || fail "n8n did not register webhook-test listener for ${workflow_id}"
}

latest_execution_record() {
  local workflow_id="$1"
  docker exec "${DB_CONTAINER_NAME}" psql -U n8n -d n8n -t -A -c "SELECT id::text || '|' || status || '|' || COALESCE(to_char(\"startedAt\", 'YYYY-MM-DD\"T\"HH24:MI:SSOF'), '') FROM execution_entity WHERE \"workflowId\" = '${workflow_id}' ORDER BY \"startedAt\" DESC LIMIT 1;"
}

require_command jq
require_command curl

[[ -f "${BUILD_WORKFLOW_PATH}" ]] || fail "Workflow file not found: ${BUILD_WORKFLOW_PATH}"
[[ -f "${ANSWER_WORKFLOW_PATH}" ]] || fail "Workflow file not found: ${ANSWER_WORKFLOW_PATH}"

copy_workflow "${BUILD_WORKFLOW_PATH}" "${BUILD_CONTAINER_PATH}" "${BUILD_WORKFLOW_NAME}"
copy_workflow "${ANSWER_WORKFLOW_PATH}" "${ANSWER_CONTAINER_PATH}" "${ANSWER_WORKFLOW_NAME}"

import_workflow "${BUILD_CONTAINER_PATH}" "${BUILD_WORKFLOW_NAME}"
import_workflow "${ANSWER_CONTAINER_PATH}" "${ANSWER_WORKFLOW_NAME}"

print_log "Listing workflows to confirm imports"
WORKFLOW_LIST_OUTPUT="$(docker exec -u "${CLI_USER}" "${CONTAINER_NAME}" n8n list:workflow 2>&1)"
print_log "${WORKFLOW_LIST_OUTPUT}"
assert_workflow_visible "${BUILD_WORKFLOW_NAME}"
assert_workflow_visible "${ANSWER_WORKFLOW_NAME}"

print_log "Minting local n8n auth cookie"
AUTH_COOKIE="$(mint_auth_cookie)"
[[ -n "${AUTH_COOKIE}" ]] || fail "Could not mint a local n8n auth cookie"

BUILD_PAYLOAD="$(cat <<'EOF'
{"memories":[{"id":1,"title":"CrispyBrain plan","content":"I am planning to build CrispyBrain incrementally using n8n, Ollama, and Postgres."},{"id":2,"title":"Next step","content":"The next planned workflow is build-context."}]}
EOF
)"

register_listener "${BUILD_WORKFLOW_ID}" "${BUILD_DESTINATION_NODE}" "${AUTH_COOKIE}"
print_log "Executing ${BUILD_WORKFLOW_NAME} through webhook-test"
post_json "${BUILD_WEBHOOK_TEST_URL}" "${BUILD_PAYLOAD}"
print_log "${LAST_HTTP_BODY}"
[[ "${LAST_HTTP_STATUS}" == "200" ]] || fail "Unexpected HTTP status from ${BUILD_WORKFLOW_NAME}: ${LAST_HTTP_STATUS}"
BUILD_OK="$(printf '%s' "${LAST_HTTP_BODY}" | jq -r '.ok')"
[[ "${BUILD_OK}" == "true" ]] || fail "${BUILD_WORKFLOW_NAME} did not return ok=true"
CONTEXT_BLOCK="$(printf '%s' "${LAST_HTTP_BODY}" | jq -r '.context')"
[[ "${CONTEXT_BLOCK}" != "null" && -n "${CONTEXT_BLOCK}" ]] || fail "${BUILD_WORKFLOW_NAME} returned an empty context"

ANSWER_PAYLOAD="$(jq -cn --arg query "${QUERY_TEXT}" --arg context "${CONTEXT_BLOCK}" '{query:$query,context:$context}')"

register_listener "${ANSWER_WORKFLOW_ID}" "${ANSWER_DESTINATION_NODE}" "${AUTH_COOKIE}"
print_log "Executing ${ANSWER_WORKFLOW_NAME} through webhook-test"
post_json "${ANSWER_WEBHOOK_TEST_URL}" "${ANSWER_PAYLOAD}"
print_log "${LAST_HTTP_BODY}"
[[ "${LAST_HTTP_STATUS}" == "200" ]] || fail "Unexpected HTTP status from ${ANSWER_WORKFLOW_NAME}: ${LAST_HTTP_STATUS}"

ANSWER_OK="$(printf '%s' "${LAST_HTTP_BODY}" | jq -r '.ok')"
ANSWER_TEXT="$(printf '%s' "${LAST_HTTP_BODY}" | jq -r '.answer')"
ANSWER_CONTEXT_LENGTH="$(printf '%s' "${LAST_HTTP_BODY}" | jq -r '.context_length')"

[[ "${ANSWER_OK}" == "true" ]] || fail "${ANSWER_WORKFLOW_NAME} did not return ok=true"
grep -Fq 'Placeholder answer' <<<"${ANSWER_TEXT}" || fail "${ANSWER_WORKFLOW_NAME} answer did not contain Placeholder answer"
[[ "${ANSWER_CONTEXT_LENGTH}" =~ ^[0-9]+$ ]] || fail "${ANSWER_WORKFLOW_NAME} returned a non-numeric context_length"
(( ANSWER_CONTEXT_LENGTH > 0 )) || fail "${ANSWER_WORKFLOW_NAME} returned context_length <= 0"

print_log "Checking n8n execution records"
BUILD_EXECUTION_RECORD="$(latest_execution_record "${BUILD_WORKFLOW_ID}")"
ANSWER_EXECUTION_RECORD="$(latest_execution_record "${ANSWER_WORKFLOW_ID}")"
print_log "${BUILD_WORKFLOW_ID}: ${BUILD_EXECUTION_RECORD}"
print_log "${ANSWER_WORKFLOW_ID}: ${ANSWER_EXECUTION_RECORD}"
[[ -n "${BUILD_EXECUTION_RECORD}" ]] || fail "No execution record found for ${BUILD_WORKFLOW_ID}"
[[ -n "${ANSWER_EXECUTION_RECORD}" ]] || fail "No execution record found for ${ANSWER_WORKFLOW_ID}"
grep -Fq '|success|' <<<"${BUILD_EXECUTION_RECORD}" || fail "${BUILD_WORKFLOW_ID} did not record a success execution"
grep -Fq '|success|' <<<"${ANSWER_EXECUTION_RECORD}" || fail "${ANSWER_WORKFLOW_ID} did not record a success execution"

pass "Both workflows imported, executed in webhook-test mode, and recorded successful n8n executions"
