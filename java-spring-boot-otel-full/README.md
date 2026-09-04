# Java Spring Boot Full OTel (Traces + Metrics + Logs)

Two Spring Boot services instrumented with OpenTelemetry, exporting traces, metrics
(delta temporality), and logs to Dynatrace via OTLP/HTTP. This is the Spring Boot
equivalent of [`python-otel-full`](../python-otel-full/).

A single jar runs in two roles, selected by the Spring profile / `spring.application.name`:

- **service-a** (port 8080) — entry point with a `/trigger` endpoint that calls service B.
- **service-b** (port 8081) — backend store with `/store` and `/data` endpoints.

Because the outbound calls use an auto-instrumented `RestClient`, A and B share a single
distributed trace.

## Setup

```bash
cp .env.example .env
# Edit .env with your DT_API_URL (ending in /api/v2/otlp) and DT_API_TOKEN
```

### Run both services + load generator

```bash
./start_all.sh
```

`start_all.sh` builds the jar (if needed), starts service-b then service-a, waits for
their `/health` endpoints, and sends requests to `/trigger` in a loop.

### Run a single service

```bash
./run.sh service-b   # backend, port 8081
./run.sh service-a   # entry point, port 8080
```

## Telemetry

- **Traces**: Spring Boot OpenTelemetry autoconfiguration, always-on sampling, exported to OTLP `/v1/traces`. Web server and `RestClient` calls are auto-instrumented.
- **Metrics**: Micrometer OTLP registry with delta temporality (required by Dynatrace), 5s step. Custom meters: `service_a_trigger_requests_total`, `service_a_trigger_latency_ms`, `service_a_service_b_calls_total`, `service_b_store_requests_total`, `service_b_data_requests_total`, `service_b_store_latency_ms`, `service_b_items_stored`.
- **Logs**: SLF4J logs bridged to OpenTelemetry and exported to OTLP `/v1/logs`.

## Configuration

| Variable | Description |
|----------|-------------|
| `DT_API_URL` | Dynatrace OTLP endpoint, e.g. `https://<env-id>.live.dynatrace.com/api/v2/otlp` |
| `DT_API_TOKEN` | API token with `openTelemetryTrace.ingest`, `metrics.ingest`, `logs.ingest` scopes |
