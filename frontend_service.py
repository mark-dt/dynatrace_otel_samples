import os

import requests
from flask import Flask, jsonify, request
from opentelemetry.trace import SpanKind, Status, StatusCode

from telemetry import configure_telemetry, extract_context, get_tracer, inject_context


SERVICE_NAME = "sample-frontend"
SERVICE_VERSION = os.getenv("FRONTEND_VERSION", "1.0.0")

configure_telemetry(SERVICE_NAME, SERVICE_VERSION)
tracer = get_tracer(SERVICE_NAME)

app = Flask(__name__)


def _inventory_url(item_id: str) -> str:
    host = os.getenv("INVENTORY_HOST", "127.0.0.1")
    port = os.getenv("INVENTORY_PORT", "8001")
    return f"http://{host}:{port}/inventory/{item_id}"


@app.get("/healthz")
def healthz():
    return {"status": "ok", "service": SERVICE_NAME, "version": SERVICE_VERSION}


@app.get("/demo/<item_id>")
def demo(item_id: str):
    incoming_context = extract_context(request.headers)

    with tracer.start_as_current_span(
        "frontend.request",
        context=incoming_context,
        kind=SpanKind.SERVER,
    ) as span:
        try:
            span.set_attribute("service.version", SERVICE_VERSION)
            span.set_attribute("app.item_id", item_id)
            span.set_attribute("http.method", request.method)
            span.set_attribute("http.route", "/demo/<item_id>")
            span.set_attribute("url.path", request.path)

            outbound_headers: dict[str, str] = {}
            inject_context(outbound_headers)

            inventory_url = _inventory_url(item_id)

            with tracer.start_as_current_span("inventory.call", kind=SpanKind.CLIENT) as client_span:
                client_span.set_attribute("http.method", "GET")
                client_span.set_attribute("url.full", inventory_url)

                response = requests.get(inventory_url, headers=outbound_headers, timeout=5)
                client_span.set_attribute("http.response.status_code", response.status_code)
                response.raise_for_status()
                inventory_payload = response.json()

            span.set_attribute("http.response.status_code", 200)
            span.set_status(Status(StatusCode.OK))

            return jsonify(
                {
                    "message": "trace sent to Dynatrace",
                    "frontend": {"service": SERVICE_NAME, "version": SERVICE_VERSION},
                    "inventory": inventory_payload,
                }
            )
        except Exception as exc:
            span.record_exception(exc)
            span.set_status(Status(StatusCode.ERROR, str(exc)))
            raise


if __name__ == "__main__":
    host = os.getenv("FRONTEND_HOST", "127.0.0.1")
    port = int(os.getenv("FRONTEND_PORT", "8000"))
    app.run(host=host, port=port)
