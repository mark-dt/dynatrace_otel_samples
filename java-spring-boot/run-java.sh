#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  set -a
  source "${SCRIPT_DIR}/.env"
  set +a
fi

export DT_TAGS="${DT_TAGS:-env=dev,team=platform,app=dummy-ms}"
export SERVER_PORT="${SERVER_PORT:-8080}"

java -jar "${SCRIPT_DIR}/target/dummy-ms-1.0.0.jar" --server.port="${SERVER_PORT}"
