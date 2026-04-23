#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

has_compose_file() {
  local candidate="${1}"
  [[ -f "${candidate}/docker-compose.yml" ]] \
    || [[ -f "${candidate}/docker-compose.yaml" ]] \
    || [[ -f "${candidate}/compose.yml" ]] \
    || [[ -f "${candidate}/compose.yaml" ]]
}

resolve_compose_file() {
  local candidate="${1}"
  local filename

  for filename in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    if [[ -f "${candidate}/${filename}" ]]; then
      printf '%s\n' "${candidate}/${filename}"
      return 0
    fi
  done

  return 1
}

resolve_compose_dir() {
  local candidate
  for candidate in "${PWD}" "${REPO_ROOT}/../crispy-ai-lab"; do
    if has_compose_file "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

resolve_version() {
  if git -C "${REPO_ROOT}" describe --tags --always >/dev/null 2>&1; then
    git -C "${REPO_ROOT}" describe --tags --always
    return 0
  fi

  if git -C "${REPO_ROOT}" rev-parse --short HEAD >/dev/null 2>&1; then
    git -C "${REPO_ROOT}" rev-parse --short HEAD
    return 0
  fi

  printf '%s\n' 'unknown-version (docker)'
}

compose_has_service() {
  local compose_file="${1}"
  local service_name="${2}"
  grep -Eq "^[[:space:]]*${service_name}:" "${compose_file}"
}

if [[ $# -eq 0 ]]; then
  echo "Usage: scripts/set-version-env.sh <docker compose args...>" >&2
  exit 1
fi

COMPOSE_DIR="$(resolve_compose_dir)" || {
  echo "Could not find a docker compose project in ${PWD} or ${REPO_ROOT}/../crispy-ai-lab" >&2
  exit 1
}
COMPOSE_FILE="$(resolve_compose_file "${COMPOSE_DIR}")" || {
  echo "Could not resolve a docker compose file in ${COMPOSE_DIR}" >&2
  exit 1
}
DEMO_INBOX_OVERRIDE_FILE="${SCRIPT_DIR}/docker-compose.crispybrain-demo-ui.inbox.override.yml"
COMPOSE_ARGS=(-f "${COMPOSE_FILE}")

export CRISPYBRAIN_APP_VERSION="$(resolve_version)"
export CRISPYBRAIN_REPO_ROOT="${REPO_ROOT}"
echo "CRISPYBRAIN_APP_VERSION=${CRISPYBRAIN_APP_VERSION}"
echo "CRISPYBRAIN_REPO_ROOT=${CRISPYBRAIN_REPO_ROOT}"

if [[ -f "${DEMO_INBOX_OVERRIDE_FILE}" ]] && compose_has_service "${COMPOSE_FILE}" "crispybrain-demo-ui"; then
  COMPOSE_ARGS+=(-f "${DEMO_INBOX_OVERRIDE_FILE}")
  echo "CRISPYBRAIN_DEMO_INBOX_OVERRIDE=${DEMO_INBOX_OVERRIDE_FILE}"
fi

cd "${COMPOSE_DIR}"
exec docker compose "${COMPOSE_ARGS[@]}" "$@"
