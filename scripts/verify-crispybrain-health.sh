#!/usr/bin/env bash
set -euo pipefail

PREFERRED_N8N_CONTAINER="${PREFERRED_N8N_CONTAINER:-crispy-ai-lab-n8n-1}"
FALLBACK_N8N_CONTAINER="${FALLBACK_N8N_CONTAINER:-ai-n8n}"
PREFERRED_DB_CONTAINER="${PREFERRED_DB_CONTAINER:-crispy-ai-lab-postgres-1}"
FALLBACK_DB_CONTAINER="${FALLBACK_DB_CONTAINER:-ai-postgres}"
DB_USER="${DB_USER:-n8n}"
DB_NAME="${DB_NAME:-n8n}"
ASSISTANT_URL="${ASSISTANT_URL:-http://localhost:5678/webhook/assistant}"
SESSION_ID="crispybrain-health-check"

failures=()
warnings=()

log_fail() {
  failures+=("$1")
  printf 'FAIL: %s\n' "$1"
}

log_pass() {
  printf 'PASS: %s\n' "$1"
}

log_warn() {
  warnings+=("$1")
  printf 'WARN: %s\n' "$1"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'FAIL: missing required command: %s\n' "$1" >&2
    exit 1
  }
}

detect_container() {
  local preferred="$1"
  local fallback="$2"
  if docker ps --format '{{.Names}}' | grep -Fxq "${preferred}"; then
    printf '%s\n' "${preferred}"
    return 0
  fi
  printf '%s\n' "${fallback}"
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

N8N_CONTAINER="${N8N_CONTAINER:-$(detect_container "${PREFERRED_N8N_CONTAINER}" "${FALLBACK_N8N_CONTAINER}")}"
DB_CONTAINER="${DB_CONTAINER:-$(detect_container "${PREFERRED_DB_CONTAINER}" "${FALLBACK_DB_CONTAINER}")}"

printf '=== CrispyBrain Health Check ===\n'

printf '\n[1/4] Workflow state\n'
docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -c "
SELECT w.name, w.active, COALESCE(f.name, '') AS folder_name
FROM workflow_entity w
LEFT JOIN folder f ON f.id = w.\"parentFolderId\"
WHERE w.name IN (
  'assistant',
  'ingest',
  'crispybrain-demo',
  'auto-ingest-watch',
  'crispybrain-assistant',
  'crispybrain-ingest',
  'crispybrain-auto-ingest-watch'
)
ORDER BY name;
"

workflow_rows="$(docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -F '|' -c "
SELECT w.name, w.active, COALESCE(f.name, '') AS folder_name
FROM workflow_entity w
LEFT JOIN folder f ON f.id = w.\"parentFolderId\"
WHERE w.name IN (
  'assistant',
  'ingest',
  'crispybrain-demo',
  'auto-ingest-watch',
  'crispybrain-assistant',
  'crispybrain-ingest',
  'crispybrain-auto-ingest-watch'
)
ORDER BY name;
")"

required_workflows=(assistant ingest crispybrain-demo)
for workflow_name in "${required_workflows[@]}"; do
  workflow_row="$(printf '%s\n' "${workflow_rows}" | grep "^${workflow_name}|")"
  if [[ -z "${workflow_row}" ]]; then
    log_fail "required workflow not found: ${workflow_name}"
    continue
  fi
  if printf '%s\n' "${workflow_row}" | grep -q '|t|'; then
    log_pass "required workflow active: ${workflow_name}"
  else
    log_fail "required workflow inactive: ${workflow_name}"
  fi
done

auto_watch_row="$(printf '%s\n' "${workflow_rows}" | grep '^auto-ingest-watch|' || true)"
if [[ -z "${auto_watch_row}" ]]; then
  log_warn 'optional workflow not found: auto-ingest-watch'
elif printf '%s\n' "${auto_watch_row}" | grep -q '|t|'; then
  log_pass 'optional workflow active: auto-ingest-watch'
else
  log_warn 'optional workflow inactive: auto-ingest-watch'
fi

canonical_folder_mismatch="$(printf '%s\n' "${workflow_rows}" | awk -F'|' '$1=="assistant" || $1=="ingest" || $1=="crispybrain-demo" { if ($3 != "CrispyBrain") print $1 "|" $3 }')"
if [[ -n "${canonical_folder_mismatch}" ]]; then
  printf '%s\n' "${canonical_folder_mismatch}" | while IFS='|' read -r name folder_name; do
    printf 'FAIL: canonical workflow in unexpected folder: %s (%s)\n' "${name}" "${folder_name:-<none>}"
  done
  failures+=("canonical workflows are not grouped under CrispyBrain")
else
  log_pass 'canonical workflows are grouped under CrispyBrain'
fi

alternate_active="$(printf '%s\n' "${workflow_rows}" | awk -F'|' '$1=="crispybrain-assistant" || $1=="crispybrain-ingest" || $1=="crispybrain-auto-ingest-watch" { if ($2 == "t") print $1 }')"
if [[ -n "${alternate_active}" ]]; then
  log_warn "alternate crispybrain-* entrypoints still active: $(printf '%s\n' "${alternate_active}" | paste -sd ',' -)"
else
  log_pass 'no alternate crispybrain-* entrypoints are active'
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
  printf 'PASS: CrispyBrain is healthy\n'
  if (( ${#warnings[@]} > 0 )); then
    for warning in "${warnings[@]}"; do
      printf ' - warning: %s\n' "${warning}"
    done
  fi
  exit 0
fi

printf 'FAIL: CrispyBrain has issues\n'
for failure in "${failures[@]}"; do
  printf ' - %s\n' "${failure}"
done
for warning in "${warnings[@]}"; do
  printf ' - warning: %s\n' "${warning}"
done
exit 1
