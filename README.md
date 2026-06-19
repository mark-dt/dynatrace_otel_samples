# Dynatrace OpenTelemetry Samples

Sample applications instrumented with OpenTelemetry, exporting telemetry to Dynatrace.

## Samples

| Directory | Language | What it does |
|-----------|----------|--------------|
| [python-service-topology](python-service-topology/) | Python / Flask | Two-service topology (frontend + inventory) with manual OTel traces sent via OTLP/HTTP |
| [python-otel-full](python-otel-full/) | Python / Flask | Two-service topology (service A + B) with full OTel: traces, metrics (delta temporality), and logs via OTLP/HTTP |
| [java-spring-boot](java-spring-boot/) | Java / Spring Boot | Single-process Spring Boot app with three simulated service endpoints and a load generator |
| [java-micrometer-otlp](java-micrometer-otlp/) | Java / Spring Boot | Micrometer metrics exported to Dynatrace via OTLP/HTTP with delta temporality |

## Configuration

All samples use a `.env` file for configuration. Each directory contains a `.env.example` you can copy:

```bash
cp <sample-dir>/.env.example <sample-dir>/.env
```

Common variables across all samples:

| Variable | Description |
|----------|-------------|
| `DT_API_URL` | Dynatrace OTLP endpoint, e.g. `https://<env-id>.live.dynatrace.com/api/v2/otlp` |
| `DT_API_TOKEN` | API token with `openTelemetryTrace.ingest`, `metrics.ingest`, `logs.ingest` scopes |

See each sample's `.env.example` for sample-specific variables.

## Running each sample

Run these from the repo root. Each script loads its `.env` and starts the service together with its load generator.

**java-micrometer-otlp** — Spring Boot app on `:8080`
```bash
cd java-micrometer-otlp && ./run.sh
```

**java-spring-boot** — Spring Boot app on `:8080`
```bash
cd java-spring-boot && cp ../.env .env && mvn -q package -DskipTests && ./run-java.sh
```

**python-otel-full** — services on `:5000` / `:5001`
```bash
cd python-otel-full && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt && ./start_all.sh
```

**python-service-topology** — frontend `:8000` / inventory `:8001`
```bash
cd python-service-topology && cp ../python-otel-full/.env .env && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt && ./start_all.sh
```

> Both Java samples bind port `8080`, so don't run them at the same time.
