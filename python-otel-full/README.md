# Python Full OTel (Traces + Metrics + Logs)

Two Python Flask services instrumented with OpenTelemetry, exporting traces, metrics (delta temporality), and logs to Dynatrace via OTLP/HTTP.

- `service_a.py` (port 5000) entry point with `/trigger` endpoint that calls service B.
- `service_b.py` (port 5001) backend store with `/store` and `/data` endpoints.

## Setup

```bash
cp .env.example .env
# Edit .env with your DT_API_URL and DT_API_TOKEN

python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
./start_all.sh
```

`run_load_gen.py` starts both services and sends requests to `/trigger`.

## Telemetry

- **Traces**: `TracerProvider` with `ALWAYS_ON` sampler, auto-instrumentation for Flask and Requests
- **Metrics**: `MeterProvider` with delta temporality (required by Dynatrace), 5s export interval, exemplars enabled
- **Logs**: Python `logging` bridged to OTel via `LoggingHandler`, exported to OTLP `/v1/logs`
