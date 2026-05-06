# Dynatrace OpenTelemetry Samples

Sample applications instrumented with OpenTelemetry, exporting telemetry to Dynatrace.

## Samples

| Directory | Language | What it does |
|-----------|----------|--------------|
| [python-service-topology](python-service-topology/) | Python / Flask | Two-service topology (frontend + inventory) with manual OTel traces sent via OTLP/HTTP |
| [python-otel-full](python-otel-full/) | Python / Flask | Two-service topology (service A + B) with full OTel: traces, metrics (delta temporality), and logs via OTLP/HTTP |
| [java-spring-boot](java-spring-boot/) | Java / Spring Boot | Single-process Spring Boot app with three simulated service endpoints and a load generator |

## Configuration

All samples use a `.env` file for configuration. Each directory contains a `.env.example` you can copy:

```bash
cp <sample-dir>/.env.example <sample-dir>/.env
```

Common variables across the Python samples:

| Variable | Description |
|----------|-------------|
| `DT_API_URL` | Dynatrace OTLP endpoint, e.g. `https://<env-id>.live.dynatrace.com/api/v2/otlp` |
| `DT_API_TOKEN` | API token with `openTelemetryTrace.ingest`, `metrics.ingest`, `logs.ingest` scopes |

See each sample's `.env.example` for sample-specific variables.

## Quick start

```bash
# Pick a sample
cd python-service-topology

# Configure
cp .env.example .env
# Edit .env with your Dynatrace environment URL and token

# Install and run
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
./start_all.sh
```
