#!/usr/bin/env bash
# Build, start service-b and service-a, then generate load against /trigger.
# Mirrors python-otel-full/run_load_gen.py.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

if [[ -z "${DT_API_URL:-}" || -z "${DT_API_TOKEN:-}" ]]; then
  echo "DT_API_URL and DT_API_TOKEN must be set. Copy .env.example to .env and fill in your values."
  exit 1
fi

JAR="target/spring-otel-full-1.0.0.jar"
if [[ ! -f "${JAR}" ]]; then
  echo "Building jar..."
  mvn -q -DskipTests package
fi

LOG_DIR="$(mktemp -d)"
A_PORT="${A_PORT:-8080}"
B_PORT="${B_PORT:-8081}"

echo "Logs: ${LOG_DIR}"

# service-b (backend store)
java -jar "${JAR}" \
  --spring.profiles.active=service-b \
  --spring.application.name=service-b \
  --server.port="${B_PORT}" \
  --management.opentelemetry.resource-attributes.dt.cost.costcenter=team_b \
  > "${LOG_DIR}/service-b.log" 2>&1 &
B_PID=$!

# service-a (entry point) — SERVICE_B_URL points it at service-b
SERVICE_B_URL="http://localhost:${B_PORT}" java -jar "${JAR}" \
  --spring.profiles.active=service-a \
  --spring.application.name=service-a \
  --server.port="${A_PORT}" \
  --management.opentelemetry.resource-attributes.dt.cost.costcenter=team_a \
  > "${LOG_DIR}/service-a.log" 2>&1 &
A_PID=$!

cleanup() {
  echo "Shutting down services..."
  kill "${A_PID}" "${B_PID}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

wait_health() {
  local url="$1"
  for _ in $(seq 1 60); do
    if curl -sf "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

echo "Waiting for services to become available..."
if ! wait_health "http://localhost:${B_PORT}/health"; then
  echo "service-b failed to start:"; tail -n 40 "${LOG_DIR}/service-b.log"; exit 1
fi
if ! wait_health "http://localhost:${A_PORT}/health"; then
  echo "service-a failed to start:"; tail -n 40 "${LOG_DIR}/service-a.log"; exit 1
fi

echo "Services are up. Generating load (Ctrl+C to stop)..."
i=0
while true; do
  i=$((i + 1))
  code="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${A_PORT}/trigger" || echo 000)"
  echo "Request ${i}: ${code}"
  sleep 0.5
done
