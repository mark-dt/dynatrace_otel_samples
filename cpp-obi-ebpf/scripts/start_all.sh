#!/usr/bin/env bash
# Starts inventory-api, pricing-api and the load generator in the background.
# OBI is deliberately NOT started here — run `make obi` in a second terminal so
# you can watch it attach and see any export errors as they happen.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

RUN_DIR=run
mkdir -p "$RUN_DIR"

if [ -f .env ]; then
  # shellcheck disable=SC1091
  set -a; . ./.env; set +a
fi

export INVENTORY_PORT="${INVENTORY_PORT:-8082}"
export PRICING_PORT="${PRICING_PORT:-8083}"
export INVENTORY_HOST="${INVENTORY_HOST:-127.0.0.1}"

for b in bin/inventory-api bin/pricing-api; do
  [ -x "$b" ] || { echo "$b not built — run: make build" >&2; exit 1; }
done

start() {
  local name="$1"; shift
  if [ -f "$RUN_DIR/$name.pid" ] && kill -0 "$(cat "$RUN_DIR/$name.pid")" 2>/dev/null; then
    echo "$name already running (pid $(cat "$RUN_DIR/$name.pid"))"
    return
  fi
  "$@" >"$RUN_DIR/$name.log" 2>&1 &
  echo $! > "$RUN_DIR/$name.pid"
  echo "started $name (pid $!) -> $RUN_DIR/$name.log"
}

start inventory-api ./bin/inventory-api
start pricing-api   ./bin/pricing-api

# Give the listeners a moment before pointing traffic at them.
sleep 1

start loadgen scripts/loadgen.sh

echo
echo "smoke test:"
curl -s "http://127.0.0.1:$PRICING_PORT/price?item=widget&qty=2" || echo "(no response yet)"
echo
echo
echo "Now start OBI in another terminal:  make obi"
echo "Stop everything with:               make stop"
