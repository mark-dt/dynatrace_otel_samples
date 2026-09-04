#!/usr/bin/env bash
# Runs OBI in the foreground with the credentials from .env.
#
# The token is passed as an environment variable rather than written into
# obi-config.yaml, so the config file stays safe to read, diff and share.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

[ -f .env ]            || { echo "no .env — run: cp .env.example .env" >&2; exit 1; }
[ -x bin/obi ]         || { echo "bin/obi missing — run: make install-obi" >&2; exit 1; }
[ -f obi-config.yaml ] || { echo "obi-config.yaml missing — run: make config" >&2; exit 1; }

# shellcheck disable=SC1091
set -a; . ./.env; set +a
: "${DT_API_TOKEN:?DT_API_TOKEN is not set in .env}"

# OBI writes its compiled eBPF objects here.
sudo mkdir -p /var/cache/obi

echo "starting OBI — Ctrl-C to stop"
echo "watch for: 'instrumenting process ... type=cpp' for both services"
echo

# Deliberately NOT `sudo -E`: only the variables OBI needs cross the boundary.
#
# The temporality preference matters — Dynatrace ingests delta counters while
# the OpenTelemetry default is cumulative.
exec sudo \
  OTEL_EXPORTER_OTLP_HEADERS="Authorization=Api-Token $DT_API_TOKEN" \
  OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=delta \
  XDG_CACHE_HOME=/var/cache/obi \
  ./bin/obi -config obi-config.yaml
