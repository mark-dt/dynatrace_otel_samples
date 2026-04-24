import os
import random
import time

from flask import Flask, jsonify, request
from opentelemetry.trace import SpanKind, Status, StatusCode

from telemetry import configure_telemetry, extract_context, get_tracer


SERVICE_NAME = "sample-inventory"
SERVICE_VERSION = os.getenv("INVENTORY_VERSION", "2.1.0")

configure_telemetry(SERVICE_NAME, SERVICE_VERSION)
tracer = get_tracer(SERVICE_NAME)

app = Flask(__name__)


@app.get("/healthz")
def healthz():
    return {"status": "ok", "service": SERVICE_NAME, "version": SERVICE_VERSION}


@app.get("/inventory/<item_id>")
def inventory(item_id: str):
    ctx = extract_context(request.headers)

    with tracer.start_as_current_span(
        "inventory.lookup",
        context=ctx,
        kind=SpanKind.SERVER,
    ) as span:
        try:
            span.set_attribute("service.version", SERVICE_VERSION)
            span.set_attribute("app.item_id", item_id)
            span.set_attribute("app.stock_location", "warehouse-a")
            span.set_attribute("http.method", request.method)
            span.set_attribute("http.route", "/inventory/<item_id>")
            span.set_attribute("url.path", request.path)

            time.sleep(random.uniform(0.03, 0.12))

            payload = {
                "item_id": item_id,
                "available": True,
                "quantity": 7,
                "service": SERVICE_NAME,
                "version": SERVICE_VERSION,
            }
            span.set_attribute("http.response.status_code", 200)
            span.set_status(Status(StatusCode.OK))
            return jsonify(payload)
        except Exception as exc:
            span.record_exception(exc)
            span.set_status(Status(StatusCode.ERROR, str(exc)))
            raise


if __name__ == "__main__":
    host = os.getenv("INVENTORY_HOST", "127.0.0.1")
    port = int(os.getenv("INVENTORY_PORT", "8001"))
    app.run(host=host, port=port)
