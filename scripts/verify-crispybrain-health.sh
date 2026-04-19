#!/usr/bin/env bash
set -euo pipefail

N8N_CONTAINER="${N8N_CONTAINER:-ai-n8n}"
DB_CONTAINER="${DB_CONTAINER:-ai-postgres}"
DB_USER="${DB_USER:-n8n}"
DB_NAME="${DB_NAME:-n8n}"
ASSISTANT_URL="${ASSISTANT_URL:-http://localhost:5678/webhook/crispybrain-assistant}"
SESSION_ID="crispybrain-health-check"

failures=()

log_fail() {
  failures+=("$1")
  printf 'FAIL: %s\n' "$1"
}

log_pass() {
  printf 'PASS: %s\n' "$1"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'FAIL: missing required command: %s\n' "$1" >&2
    exit 1
  }
}

check_http_json() {
  local payload="$1"
  local response
  response="$(curl -sS -X POST "${ASSISTANT_URL}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    -w $'\nHTTP_STATUS:%{http_code}')" || return 1
  HTTP_STATUS="$(printf '%s\n' "${response}" | tail -n 1 | sed 's/^HTTP_STATUS://')"
  HTTP_BODY="$(printf '%s\n' "${response}" | sed '$d')"
  return 0
}

require_cmd docker
require_cmd curl
require_cmd grep
require_cmd sh

printf '=== CrispyBrain v0.4 Health Check ===\n'

printf '\n[1/4] Workflow state\n'
docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -c "
SELECT name, active
FROM workflow_entity
WHERE name LIKE 'crispybrain-%' OR name = 'assistant'
ORDER BY name;
"

workflow_rows="$(docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -F '|' -c "
SELECT name, active
FROM workflow_entity
WHERE name LIKE 'crispybrain-%' OR name = 'assistant'
ORDER BY name;
")"

assistant_row="$(printf '%s\n' "${workflow_rows}" | grep '^assistant|')"
if printf '%s\n' "${assistant_row}" | grep -q '|t$'; then
  log_fail 'legacy workflow "assistant" is active'
else
  log_pass 'legacy workflow "assistant" is inactive'
fi

inactive_crispybrain="$(printf '%s\n' "${workflow_rows}" | grep '^crispybrain-' | grep '|f$' || true)"
if [[ -n "${inactive_crispybrain}" ]]; then
  printf '%s\n' "${inactive_crispybrain}" | while IFS='|' read -r name active; do
    printf 'FAIL: crispybrain workflow inactive: %s\n' "${name}"
  done
  failures+=("one or more crispybrain workflows are inactive")
else
  log_pass 'all crispybrain-* workflows are active'
fi

printf '\n[2/4] Recent n8n logs\n'
recent_logs="$(docker logs --since 60s "${N8N_CONTAINER}" 2>&1 || true)"
if printf '%s\n' "${recent_logs}" | grep -q 'dbTime.getTime is not a function'; then
  log_fail 'recent n8n logs contain dbTime.getTime is not a function'
else
  log_pass 'recent n8n logs are free of dbTime.getTime errors'
fi

printf '\n[3/4] Assistant continuity test\n'
first_payload='{
  "message": "What is CrispyBrain?",
  "session_id": "'"${SESSION_ID}"'",
  "top_k": 4
}'
second_payload='{
  "message": "Explain that more simply.",
  "session_id": "'"${SESSION_ID}"'",
  "top_k": 4
}'

HTTP_STATUS=""
HTTP_BODY=""
if ! check_http_json "${first_payload}"; then
  log_fail 'first assistant request failed to execute'
else
  if [[ "${HTTP_STATUS}" != "200" || -z "${HTTP_BODY}" ]]; then
    log_fail "first assistant request returned HTTP ${HTTP_STATUS:-unknown} or empty body"
  else
    log_pass 'first assistant request returned HTTP 200 with a JSON body'
  fi
fi

HTTP_STATUS=""
HTTP_BODY=""
if ! check_http_json "${second_payload}"; then
  log_fail 'second assistant request failed to execute'
else
  second_body="${HTTP_BODY}"
  if [[ "${HTTP_STATUS}" != "200" ]]; then
    log_fail "second assistant request returned HTTP ${HTTP_STATUS}"
  elif [[ -z "${second_body}" ]]; then
    log_fail 'second assistant request returned an empty body'
  elif printf '%s' "${second_body}" | grep -qi 'not enough stored memory'; then
    log_fail 'second assistant response contained "not enough stored memory"'
  elif ! printf '%s' "${second_body}" | grep -q '"ok":[[:space:]]*true'; then
    log_fail 'second assistant response did not contain "ok": true'
  else
    log_pass 'second assistant response passed continuity checks'
  fi
fi

printf '\n[4/4] Final summary\n'
if (( ${#failures[@]} == 0 )); then
  printf 'PASS: CrispyBrain v0.4 is healthy\n'
  exit 0
fi

printf 'FAIL: CrispyBrain v0.4 has issues\n'
for failure in "${failures[@]}"; do
  printf ' - %s\n' "${failure}"
done
exit 1
