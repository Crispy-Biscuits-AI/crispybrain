#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKFLOW_PATH="${REPO_ROOT}/workflows/smoke-test.json"
CONTAINER_NAME="ai-n8n"
DB_CONTAINER_NAME="ai-postgres"
CONTAINER_WORKFLOW_PATH="/tmp/smoke-test.json"
WORKFLOW_NAME="smoke-test"
WORKFLOW_ID="smoke-test"
WORKFLOW_NODE_NAME="Smoke Test Payload"
CLI_USER="node"
REST_BASE_URL="http://localhost:5678/rest"
WEBHOOK_TEST_URL="http://localhost:5678/webhook-test/smoke-test"
COOKIE_NAME="n8n-auth"
TEMP_COOKIE_FILE="/tmp/smoke-test.cookie"
EXECUTION_QUERY="SELECT id::text || '|' || status || '|' || COALESCE(to_char(\"startedAt\", 'YYYY-MM-DD\"T\"HH24:MI:SSOF'), '') FROM execution_entity WHERE \"workflowId\" = '${WORKFLOW_ID}' ORDER BY \"startedAt\" DESC LIMIT 1;"

print_log() {
  printf '%s\n' "$1"
}

pass() {
  print_log "PASS: $1"
  exit 0
}

fail() {
  print_log "FAIL: $1" >&2
  exit 1
}

cleanup() {
  rm -f "${TEMP_COOKIE_FILE}"
}

trap cleanup EXIT

if [[ ! -f "${WORKFLOW_PATH}" ]]; then
  fail "Workflow file not found at ${WORKFLOW_PATH}"
fi

print_log "Copying workflow into ${CONTAINER_NAME}:${CONTAINER_WORKFLOW_PATH}"
copy_output="$(docker cp "${WORKFLOW_PATH}" "${CONTAINER_NAME}:${CONTAINER_WORKFLOW_PATH}" 2>&1)"
if [[ -n "${copy_output}" ]]; then
  print_log "${copy_output}"
fi

print_log "Importing workflow into n8n"
import_output="$(docker exec -u "${CLI_USER}" "${CONTAINER_NAME}" n8n import:workflow --input="${CONTAINER_WORKFLOW_PATH}" 2>&1)"
print_log "${import_output}"
if ! grep -Eq 'Successfully imported [0-9]+ workflow|Imported [0-9]+ workflow' <<<"${import_output}"; then
  fail "Workflow import output did not report a successful import"
fi

print_log "Listing workflows to confirm ${WORKFLOW_NAME} exists"
list_output="$(docker exec -u "${CLI_USER}" "${CONTAINER_NAME}" n8n list:workflow 2>&1)"
print_log "${list_output}"
if ! grep -Fq "${WORKFLOW_NAME}" <<<"${list_output}"; then
  fail "Imported workflow was not found in workflow list"
fi

print_log "Loading local n8n user metadata for authenticated test registration"
user_record="$(docker exec "${DB_CONTAINER_NAME}" psql -U n8n -d n8n -t -A -c "SELECT id || '|' || email || '|' || password || '|' || CASE WHEN \"mfaEnabled\" THEN 't' ELSE 'f' END || '|' || COALESCE(\"mfaSecret\", '') FROM \"user\" LIMIT 1;" 2>&1)"
if [[ -z "${user_record}" ]]; then
  fail "Could not read n8n user metadata"
fi
IFS='|' read -r user_id user_email user_password_hash user_mfa_enabled user_mfa_secret <<<"${user_record}"
if [[ -z "${user_id}" || -z "${user_email}" || -z "${user_password_hash}" ]]; then
  fail "Incomplete n8n user metadata: ${user_record}"
fi

print_log "Minting local auth cookie for /rest/workflows/${WORKFLOW_ID}/run"
auth_cookie="$(docker exec -u "${CLI_USER}" "${CONTAINER_NAME}" sh -lc "cd /usr/local/lib/node_modules/n8n && node -e \"const fs=require('fs'); const crypto=require('crypto'); const jwt=require('jsonwebtoken'); const [userId,email,password,mfaEnabled,mfaSecret]=process.argv.slice(1); const config=JSON.parse(fs.readFileSync('/home/node/.n8n/config','utf8')); let jwtSecret=config.userManagement?.jwtSecret || ''; if (!jwtSecret) { let baseKey=''; for (let i=0; i<config.encryptionKey.length; i+=2) baseKey+=config.encryptionKey[i]; jwtSecret=crypto.createHash('sha256').update(baseKey).digest('hex'); } const payload=[email,password]; if (mfaEnabled === 't' && mfaSecret) payload.push(mfaSecret.substring(0, 3)); const hash=crypto.createHash('sha256').update(payload.join(':')).digest('base64').substring(0, 10); const token=jwt.sign({ id:userId, hash, usedMfa:false }, jwtSecret, { expiresIn: 3600 }); process.stdout.write(token);\" '${user_id}' '${user_email}' '${user_password_hash}' '${user_mfa_enabled}' '${user_mfa_secret}'" 2>&1)"
if [[ -z "${auth_cookie}" ]]; then
  fail "Could not mint a local n8n auth cookie"
fi
printf '%s=%s\n' "${COOKIE_NAME}" "${auth_cookie}" > "${TEMP_COOKIE_FILE}"

print_log "Registering webhook-test listener via n8n manual run API"
run_output="$(curl -sS -X POST "${REST_BASE_URL}/workflows/${WORKFLOW_ID}/run" \
  -H 'Content-Type: application/json' \
  -H "Cookie: ${COOKIE_NAME}=${auth_cookie}" \
  --data "{\"destinationNode\":{\"nodeName\":\"${WORKFLOW_NODE_NAME}\"}}" 2>&1)"
print_log "${run_output}"
if ! grep -Fq 'waitingForWebhook' <<<"${run_output}"; then
  fail "n8n did not register a webhook-test listener"
fi

print_log "Executing workflow through ${WEBHOOK_TEST_URL}"
response_body="$(curl -sS -X POST "${WEBHOOK_TEST_URL}" -H 'Content-Type: application/json' --data '{"smoke":"test"}' 2>&1)"
print_log "${response_body}"
if ! grep -Fq '"status":"ok"' <<<"${response_body}"; then
  fail "Webhook response did not contain status=ok"
fi
if ! grep -Fq '"source":"smoke-test"' <<<"${response_body}"; then
  fail "Webhook response did not contain source=smoke-test"
fi

print_log "Checking n8n execution records"
execution_record="$(docker exec "${DB_CONTAINER_NAME}" psql -U n8n -d n8n -t -A -c "${EXECUTION_QUERY}" 2>&1)"
print_log "${execution_record}"
if [[ -z "${execution_record}" ]]; then
  fail "No execution record found for ${WORKFLOW_ID}"
fi

pass "Workflow imported, executed through webhook-test, and recorded in n8n executions"
