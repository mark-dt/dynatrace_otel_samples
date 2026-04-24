# Dynatrace OpenTelemetry Python Samples

This project contains two small Python services that manually create spans and send traces to Dynatrace over OTLP/HTTP, following the Dynatrace manual instrumentation walkthrough:

- https://docs.dynatrace.com/docs/ingest-from/opentelemetry/walkthroughs/python/python-manual
- https://docs.dynatrace.com/docs/ingest-from/opentelemetry/otlp-api

Each service sets both:

- `service.name`
- `service.version`

## Services

- `frontend_service.py` receives the incoming request and calls the inventory service.
- `inventory_service.py` handles the downstream request and continues the same trace.

## Setup

1. Create and activate a virtual environment.
2. Install dependencies:

```bash
pip install -r requirements.txt
```

3. Export the required Dynatrace settings:

```bash
export DT_API_URL="https://your-environment-id.live.dynatrace.com/api/v2/otlp"
export DT_API_TOKEN="dt0c01.your-token"
```

The base URL must end with `/api/v2/otlp`. The services append `/v1/traces` automatically.
On startup, each service performs a small OTLP preflight request and exits early if the endpoint is unreachable or the token is rejected.

## Run

Start the inventory service:

```bash
OTEL_RESOURCE_ATTRIBUTES="primary_tags.release=12345,primary_tags.version=2.1.0,deployment.environment=dev" INVENTORY_VERSION=2.1.0 python inventory_service.py
```

Start the frontend service in a second terminal:

```bash
OTEL_RESOURCE_ATTRIBUTES="primary_tags.release=12345,primary_tags.version=1.0.0,deployment.environment=dev" FRONTEND_VERSION=1.0.0 python frontend_service.py
```

Generate a trace:

```bash
curl http://127.0.0.1:8000/demo/widget-123
```

Or start both services together:

```bash
./start_all.sh
```

`start_all.sh` also starts `load_generator.py` against the frontend by default. Tune it with `LOADGEN_SECONDS`, `LOADGEN_REQUESTS_PER_SECOND`, `LOADGEN_CONCURRENCY`, `LOADGEN_TIMEOUT`, and `LOADGEN_ITEM_PREFIX`. Set `LOADGEN_SECONDS=0` to keep generating traffic until you stop the script.

Generate continuous traffic with the load generator:

```bash
python load_generator.py --seconds 120 --requests-per-second 2 --concurrency 2 --item-prefix widget
```

## What To Expect

- Dynatrace should show traces for `sample-frontend` and `sample-inventory`.
- The frontend span and downstream inventory span should appear in the same distributed trace.
- The service entities should include the configured `service.version` values.

## Helper Scripts

- `start_all.sh` starts both Flask services in the background and writes logs to `.run/`.
- `load_generator.py` sends a small wave of requests every second to the frontend service and prints a small summary at the end.
# dynatrace_otel_samples
