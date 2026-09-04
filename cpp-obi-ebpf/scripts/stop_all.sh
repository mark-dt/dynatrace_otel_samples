#!/usr/bin/env bash
# Stops whatever start_all.sh started. OBI runs in the foreground under `make
# obi`, so it is not managed here — Ctrl-C it in its own terminal.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

RUN_DIR=run
[ -d "$RUN_DIR" ] || { echo "nothing to stop"; exit 0; }

for pidfile in "$RUN_DIR"/*.pid; do
  [ -e "$pidfile" ] || continue
  name=$(basename "$pidfile" .pid)
  pid=$(cat "$pidfile")
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
    echo "stopped $name (pid $pid)"
  else
    echo "$name was not running"
  fi
  rm -f "$pidfile"
done
