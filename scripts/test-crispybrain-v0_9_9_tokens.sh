#!/usr/bin/env bash

set -euo pipefail

DEMO_URL="${DEMO_URL:-http://localhost:5678/webhook/crispybrain-demo}"
SESSION_ID="${SESSION_ID:-crispybrain-v0-9-9-token-check}"
PROMPT_1="${PROMPT_1:-How am I planning to build CrispyBrain?}"
PROMPT_2="${PROMPT_2:-List the strongest current CrispyBrain capabilities visible in the repo in one short paragraph.}"
PROMPT_3="${PROMPT_3:-What does echo marker mean?}"
UNAVAILABLE_PROJECT_SLUG="${UNAVAILABLE_PROJECT_SLUG:-omega-missing-token-usage}"

http_status=""
http_body=""

post_json() {
  local payload="$1"
  local raw
  raw="$(curl -sS -X POST "${DEMO_URL}" -H 'Content-Type: application/json' --data "${payload}" -w $'\nHTTP_STATUS:%{http_code}')"
  http_status="$(printf '%s\n' "${raw}" | tail -n 1 | sed 's/^HTTP_STATUS://')"
  http_body="$(printf '%s\n' "${raw}" | sed '$d')"
}

require_ok_usage() {
  local body="$1"
  local label="$2"
  printf '%s' "${body}" | jq -e '
    .ok == true
    and .usage.available == true
    and (.usage.input_tokens | numbers) > 0
    and (.usage.output_tokens | numbers) > 0
    and (.usage.total_tokens | numbers) == ((.usage.input_tokens | numbers) + (.usage.output_tokens | numbers))
  ' >/dev/null || {
    printf 'FAIL: %s did not return provider-reported usage\n' "${label}" >&2
    printf '%s\n' "${body}" >&2
    exit 1
  }
}

require_unavailable_usage() {
  local body="$1"
  printf '%s' "${body}" | jq -e '
    .ok == true
    and .answer_mode == "insufficient"
    and .usage.available == false
    and .usage.input_tokens == null
    and .usage.output_tokens == null
    and .usage.total_tokens == null
    and .usage.reason == "answer_not_generated"
  ' >/dev/null || {
    printf 'FAIL: unavailable usage path did not stay explicit\n' >&2
    printf '%s\n' "${body}" >&2
    exit 1
  }
}

payload_1="$(jq -cn --arg project_slug "alpha" --arg question "${PROMPT_1}" --arg session_id "${SESSION_ID}" '{project_slug: $project_slug, question: $question, session_id: $session_id}')"
post_json "${payload_1}"
[[ "${http_status}" == "200" ]] || {
  printf 'FAIL: prompt 1 returned HTTP %s\n' "${http_status}" >&2
  exit 1
}
response_1="${http_body}"
require_ok_usage "${response_1}" 'prompt 1'

payload_2="$(jq -cn --arg project_slug "alpha" --arg question "${PROMPT_2}" --arg session_id "${SESSION_ID}" '{project_slug: $project_slug, question: $question, session_id: $session_id}')"
post_json "${payload_2}"
[[ "${http_status}" == "200" ]] || {
  printf 'FAIL: prompt 2 returned HTTP %s\n' "${http_status}" >&2
  exit 1
}
response_2="${http_body}"
require_ok_usage "${response_2}" 'prompt 2'

answer_1="$(printf '%s' "${response_1}" | jq -r '.answer')"
answer_2="$(printf '%s' "${response_2}" | jq -r '.answer')"
input_tokens_1="$(printf '%s' "${response_1}" | jq -r '.usage.input_tokens')"
input_tokens_2="$(printf '%s' "${response_2}" | jq -r '.usage.input_tokens')"

[[ "${answer_1}" != "${answer_2}" ]] || {
  printf 'FAIL: prompt 1 and prompt 2 returned the same answer text\n' >&2
  exit 1
}
[[ "${input_tokens_1}" != "${input_tokens_2}" ]] || {
  printf 'FAIL: prompt 1 and prompt 2 returned the same input token count\n' >&2
  exit 1
}

payload_3="$(jq -cn --arg project_slug "${UNAVAILABLE_PROJECT_SLUG}" --arg question "${PROMPT_3}" --arg session_id "${SESSION_ID}" '{project_slug: $project_slug, question: $question, session_id: $session_id}')"
post_json "${payload_3}"
[[ "${http_status}" == "200" ]] || {
  printf 'FAIL: prompt 3 returned HTTP %s\n' "${http_status}" >&2
  exit 1
}
response_3="${http_body}"
require_unavailable_usage "${response_3}"

printf 'PASS: prompt 1 input_tokens=%s output_tokens=%s total_tokens=%s\n' \
  "$(printf '%s' "${response_1}" | jq -r '.usage.input_tokens')" \
  "$(printf '%s' "${response_1}" | jq -r '.usage.output_tokens')" \
  "$(printf '%s' "${response_1}" | jq -r '.usage.total_tokens')"

printf 'PASS: prompt 2 input_tokens=%s output_tokens=%s total_tokens=%s\n' \
  "$(printf '%s' "${response_2}" | jq -r '.usage.input_tokens')" \
  "$(printf '%s' "${response_2}" | jq -r '.usage.output_tokens')" \
  "$(printf '%s' "${response_2}" | jq -r '.usage.total_tokens')"

printf 'PASS: prompt 3 usage available=%s reason=%s\n' \
  "$(printf '%s' "${response_3}" | jq -r '.usage.available')" \
  "$(printf '%s' "${response_3}" | jq -r '.usage.reason')"
