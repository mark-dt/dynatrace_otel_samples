#!/usr/bin/env bash
# Generates obi-config.yaml from the template, filling in DT_API_URL from .env
# and the absolute path to bin/.
# Usage: gen-config.sh <template> <output> <abs-bin-dir>
set -euo pipefail

TEMPLATE="$1"
OUT="$2"
ABS_BIN="$3"

[ -f .env ] || { echo "no .env — run: cp .env.example .env" >&2; exit 1; }

# shellcheck disable=SC1091
set -a; . ./.env; set +a

: "${DT_API_URL:?DT_API_URL is not set in .env}"

# A trailing slash would produce .../api/v2/otlp//v1/traces, which Dynatrace
# rejects with a 404 that looks exactly like the wrong-path mistake.
DT_API_URL="${DT_API_URL%/}"

case "$DT_API_URL" in
  */api/v2/otlp) ;;
  *) echo "warning: DT_API_URL does not end in /api/v2/otlp — got $DT_API_URL" >&2 ;;
esac

sed -e "s|__DT_API_URL__|$DT_API_URL|g" \
    -e "s|__BIN_DIR__|$ABS_BIN|g" \
    "$TEMPLATE" > "$OUT"

echo "wrote $OUT"
echo "  traces  -> $DT_API_URL/v1/traces"
echo "  metrics -> $DT_API_URL/v1/metrics"
echo "  watching $ABS_BIN/{pricing-api,inventory-api}"
