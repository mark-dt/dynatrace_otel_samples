#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="${ROOT_DIR}/.run"
PYTHON_BIN="${ROOT_DIR}/.venv/bin/python"

mkdir -p "${RUN_DIR}"

if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a
  source "${ROOT_DIR}/.env"
  set +a
fi

export FRONTEND_HOST="${FRONTEND_HOST:-127.0.0.1}"
export FRONTEND_PORT="${FRONTEND_PORT:-8000}"
export FRONTEND_VERSION="${FRONTEND_VERSION:-1.0.0}"

export INVENTORY_HOST="${INVENTORY_HOST:-127.0.0.1}"
export INVENTORY_PORT="${INVENTORY_PORT:-8001}"
export INVENTORY_VERSION="${INVENTORY_VERSION:-2.1.0}"
export OTEL_RESOURCE_ATTRIBUTES="${OTEL_RESOURCE_ATTRIBUTES:-primary_tags.release=12345,deployment.environment=dev}"

export LOADGEN_SECONDS="${LOADGEN_SECONDS:-0}"
export LOADGEN_REQUESTS_PER_SECOND="${LOADGEN_REQUESTS_PER_SECOND:-2}"
export LOADGEN_CONCURRENCY="${LOADGEN_CONCURRENCY:-2}"
export LOADGEN_TIMEOUT="${LOADGEN_TIMEOUT:-5.0}"
export LOADGEN_ITEM_PREFIX="${LOADGEN_ITEM_PREFIX:-widget}"

if [[ -z "${DT_API_URL:-}" || -z "${DT_API_TOKEN:-}" ]]; then
  echo "DT_API_URL and DT_API_TOKEN must be set before starting the services."
  exit 1
fi

if [[ ! -x "${PYTHON_BIN}" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python3)"
  else
    echo "No Python interpreter found."
    exit 1
  fi
fi

kill_pid_file() {
  local pid_file="$1"

  if [[ -f "${pid_file}" ]]; then
    kill "$(cat "${pid_file}")" 2>/dev/null || true
    rm -f "${pid_file}"
  fi
}

kill_port_listener() {
  local port="$1"

  if command -v lsof >/dev/null 2>&1; then
    while IFS= read -r pid; do
      [[ -n "${pid}" ]] || continue
      kill "${pid}" 2>/dev/null || true
    done < <(lsof -tiTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true)
  fi
}

kill_matching_processes() {
  local pattern="$1"

  if command -v pgrep >/dev/null 2>&1; then
    while IFS= read -r pid; do
      [[ -n "${pid}" ]] || continue
      kill "${pid}" 2>/dev/null || true
    done < <(pgrep -f "${pattern}" 2>/dev/null || true)
  fi
}

build_resource_attributes() {
  local version="$1"

  if [[ "${OTEL_RESOURCE_ATTRIBUTES}" == *"primary_tags.version="* ]]; then
    printf '%s\n' "${OTEL_RESOURCE_ATTRIBUTES}"
  else
    printf '%s,primary_tags.version=%s\n' "${OTEL_RESOURCE_ATTRIBUTES}" "${version}"
  fi
}

stop_existing_processes() {
  kill_pid_file "${RUN_DIR}/inventory.pid"
  kill_pid_file "${RUN_DIR}/frontend.pid"
  kill_pid_file "${RUN_DIR}/loadgen.pid"

  kill_matching_processes "${ROOT_DIR}/inventory_service.py"
  kill_matching_processes "${ROOT_DIR}/frontend_service.py"
  kill_matching_processes "${ROOT_DIR}/load_generator.py"

  kill_port_listener "${INVENTORY_PORT}"
  kill_port_listener "${FRONTEND_PORT}"
}

cleanup() {
  local exit_code=$?

  kill_pid_file "${RUN_DIR}/inventory.pid"
  kill_pid_file "${RUN_DIR}/frontend.pid"
  kill_pid_file "${RUN_DIR}/loadgen.pid"

  exit "${exit_code}"
}

trap cleanup EXIT INT TERM

stop_existing_processes

INVENTORY_RESOURCE_ATTRIBUTES="$(build_resource_attributes "${INVENTORY_VERSION}")"
FRONTEND_RESOURCE_ATTRIBUTES="$(build_resource_attributes "${FRONTEND_VERSION}")"

OTEL_RESOURCE_ATTRIBUTES="${INVENTORY_RESOURCE_ATTRIBUTES}" \
  "${PYTHON_BIN}" "${ROOT_DIR}/inventory_service.py" >"${RUN_DIR}/inventory.log" 2>&1 &
echo $! >"${RUN_DIR}/inventory.pid"

OTEL_RESOURCE_ATTRIBUTES="${FRONTEND_RESOURCE_ATTRIBUTES}" \
  "${PYTHON_BIN}" "${ROOT_DIR}/frontend_service.py" >"${RUN_DIR}/frontend.log" 2>&1 &
echo $! >"${RUN_DIR}/frontend.pid"

sleep 2

if ! kill -0 "$(cat "${RUN_DIR}/inventory.pid")" 2>/dev/null; then
  echo "Inventory service failed to start."
  sed -n '1,120p' "${RUN_DIR}/inventory.log"
  exit 1
fi

if ! kill -0 "$(cat "${RUN_DIR}/frontend.pid")" 2>/dev/null; then
  echo "Frontend service failed to start."
  sed -n '1,120p' "${RUN_DIR}/frontend.log"
  exit 1
fi

"${PYTHON_BIN}" "${ROOT_DIR}/load_generator.py" \
  --url "http://${FRONTEND_HOST}:${FRONTEND_PORT}/demo" \
  --seconds "${LOADGEN_SECONDS}" \
  --requests-per-second "${LOADGEN_REQUESTS_PER_SECOND}" \
  --concurrency "${LOADGEN_CONCURRENCY}" \
  --timeout "${LOADGEN_TIMEOUT}" \
  --item-prefix "${LOADGEN_ITEM_PREFIX}" >"${RUN_DIR}/loadgen.log" 2>&1 &
echo $! >"${RUN_DIR}/loadgen.pid"

sleep 1

if ! kill -0 "$(cat "${RUN_DIR}/loadgen.pid")" 2>/dev/null; then
  echo "Load generator failed to start."
  sed -n '1,120p' "${RUN_DIR}/loadgen.log"
  exit 1
fi

echo "Inventory service: http://${INVENTORY_HOST}:${INVENTORY_PORT}"
echo "Frontend service:  http://${FRONTEND_HOST}:${FRONTEND_PORT}"
echo "Load generator:    http://${FRONTEND_HOST}:${FRONTEND_PORT}/demo"
echo "Logs: ${RUN_DIR}"
echo "Python: ${PYTHON_BIN}"
echo "Press Ctrl+C to stop both services."

wait
