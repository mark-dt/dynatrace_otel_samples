#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://localhost:8080}"
# DURATION_SEC="${2:-60}"
DURATION_SEC="36000"
CONCURRENCY="${3:-10}"

end=$((SECONDS + DURATION_SEC))

hit() {
  while [ $SECONDS -lt $end ]; do
    case $((RANDOM % 3)) in
      0) curl -sS "${BASE_URL}/service-a/hello" >/dev/null ;;
      1) curl -sS "${BASE_URL}/service-b/compute?n=$((20000 + RANDOM % 40000))" >/dev/null ;;
      2) curl -sS "${BASE_URL}/service-c/flaky?errorRate=0.$((RANDOM % 15))" >/dev/null ;;
    esac
  done
}

for _ in $(seq 1 "$CONCURRENCY"); do
  hit &
done
wait
echo "Done."
