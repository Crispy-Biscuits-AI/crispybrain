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

if [[ $# -eq 0 ]]; then
  echo "Usage: scripts/set-version-env.sh <docker compose args...>" >&2
  exit 1
fi

COMPOSE_DIR="$(resolve_compose_dir)" || {
  echo "Could not find a docker compose project in ${PWD} or ${REPO_ROOT}/../crispy-ai-lab" >&2
  exit 1
}

export CRISPYBRAIN_APP_VERSION="$(resolve_version)"
echo "CRISPYBRAIN_APP_VERSION=${CRISPYBRAIN_APP_VERSION}"

cd "${COMPOSE_DIR}"
exec docker compose "$@"
