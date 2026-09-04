#!/usr/bin/env bash
# Run a single service. Usage: ./run.sh [service-a|service-b]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLE="${1:-service-a}"

if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  set -a
  source "${SCRIPT_DIR}/.env"
  set +a
fi

if [[ -z "${DT_API_URL:-}" || -z "${DT_API_TOKEN:-}" ]]; then
  echo "DT_API_URL and DT_API_TOKEN must be set. Copy .env.example to .env and fill in your values."
  exit 1
fi

JAR="${SCRIPT_DIR}/target/spring-otel-full-1.0.0.jar"
if [[ ! -f "${JAR}" ]]; then
  echo "Building jar..."
  (cd "${SCRIPT_DIR}" && mvn -q -DskipTests package)
fi

case "${ROLE}" in
  service-a) PORT="${SERVER_PORT:-8080}"; TEAM="team_a" ;;
  service-b) PORT="${SERVER_PORT:-8081}"; TEAM="team_b" ;;
  *) echo "Unknown role: ${ROLE} (use service-a or service-b)"; exit 1 ;;
esac

exec java -jar "${JAR}" \
  --spring.profiles.active="${ROLE}" \
  --spring.application.name="${ROLE}" \
  --server.port="${PORT}" \
  --management.opentelemetry.resource-attributes.dt.cost.costcenter="${TEAM}"
