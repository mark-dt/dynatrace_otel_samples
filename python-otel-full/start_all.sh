#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  set -a
  source "${SCRIPT_DIR}/.env"
  set +a
fi

if [[ -z "${DT_API_URL:-}" || -z "${DT_API_TOKEN:-}" ]]; then
  echo "DT_API_URL and DT_API_TOKEN must be set. Copy .env.example to .env and fill in your values."
  exit 1
fi

exec python3 "${SCRIPT_DIR}/run_load_gen.py"
