#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKFLOW_PATH="${REPO_ROOT}/workflows/openbrain-smoke-test.json"
CONTAINER_NAME="ai-n8n"
CONTAINER_WORKFLOW_PATH="/tmp/openbrain-smoke-test.json"
WORKFLOW_NAME="openbrain-smoke-test"
CLI_USER="node"

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

if [[ ! -f "${WORKFLOW_PATH}" ]]; then
  fail "Workflow file not found at ${WORKFLOW_PATH}"
fi

print_log "Copying workflow into ${CONTAINER_NAME}:${CONTAINER_WORKFLOW_PATH}"
copy_output="$(docker cp "${WORKFLOW_PATH}" "${CONTAINER_NAME}:${CONTAINER_WORKFLOW_PATH}" 2>&1)"
copy_status=$?
if [[ ${copy_status} -ne 0 ]]; then
  print_log "${copy_output}"
  fail "docker cp failed"
fi
if [[ -n "${copy_output}" ]]; then
  print_log "${copy_output}"
fi

print_log "Importing workflow into n8n"
import_output="$(docker exec -u "${CLI_USER}" "${CONTAINER_NAME}" n8n import:workflow --input="${CONTAINER_WORKFLOW_PATH}" 2>&1)"
import_status=$?
print_log "${import_output}"
if [[ ${import_status} -ne 0 ]]; then
  fail "Workflow import command failed"
fi

if ! grep -Eq 'Successfully imported [0-9]+ workflow|Imported [0-9]+ workflow' <<<"${import_output}"; then
  fail "Workflow import output did not report a successful import"
fi

print_log "Listing workflows to confirm ${WORKFLOW_NAME} exists"
list_output="$(docker exec -u "${CLI_USER}" "${CONTAINER_NAME}" n8n list:workflow 2>&1)"
list_status=$?
print_log "${list_output}"
if [[ ${list_status} -ne 0 ]]; then
  fail "Workflow list command failed"
fi

if ! grep -Fq "${WORKFLOW_NAME}" <<<"${list_output}"; then
  fail "Imported workflow was not found in workflow list"
fi

pass "Workflow imported and verified in ${CONTAINER_NAME}"
