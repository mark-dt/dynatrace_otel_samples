# Python Service Topology (Traces)

Two Python Flask services that manually create spans and send traces to Dynatrace over OTLP/HTTP.

- `frontend_service.py` (port 8000) receives the incoming request and calls the inventory service.
- `inventory_service.py` (port 8001) handles the downstream request and continues the same trace.

## Setup

```bash
cp .env.example .env
# Edit .env with your DT_API_URL and DT_API_TOKEN

python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
./start_all.sh
```

`start_all.sh` starts both services and a load generator. Tune with `LOADGEN_SECONDS`, `LOADGEN_REQUESTS_PER_SECOND`, etc. in your `.env`.

## Generate a single trace

```bash
curl http://127.0.0.1:8000/demo/widget-123
```
