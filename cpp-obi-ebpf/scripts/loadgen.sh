#!/usr/bin/env bash
# Steady traffic against pricing-api so the RED metrics have something to show.
#
# Mixes items and quantities to give http.route and status-code dimensions more
# than one value, and asks for a nonexistent route every tenth cycle so the 4xx
# bucket is populated too.
set -uo pipefail

PORT="${PRICING_PORT:-8083}"
BASE="http://127.0.0.1:$PORT"
ITEMS=(widget gizmo sprocket flange unobtainium)

i=0
while true; do
  item=${ITEMS[$((RANDOM % ${#ITEMS[@]}))]}
  qty=$((1 + RANDOM % 6))
  curl -s -o /dev/null \
    -w "[loadgen] GET /price item=$item qty=$qty -> %{http_code} in %{time_total}s\n" \
    "$BASE/price?item=$item&qty=$qty" || echo "[loadgen] request failed"

  i=$((i + 1))
  if [ $((i % 10)) -eq 0 ]; then
    curl -s -o /dev/null -w "[loadgen] GET /nope -> %{http_code}\n" \
      "$BASE/nope" || true
  fi

  sleep 3
done
