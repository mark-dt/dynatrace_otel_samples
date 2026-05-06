import atexit
import json
import logging
import os
from typing import Mapping, Sequence

from dotenv import load_dotenv

load_dotenv()

import requests
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.proto.collector.trace.v1.trace_service_pb2 import (
    ExportTraceServiceRequest,
)
from opentelemetry.propagate import inject
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import ReadableSpan
from opentelemetry.sdk.trace import TracerProvider, sampling
from opentelemetry.sdk.trace.export import BatchSpanProcessor, SpanExportResult
from opentelemetry.trace import set_tracer_provider
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator


_METADATA_FILES = [
    "dt_metadata_e617c525669e072eebe3d0f08212e8f2.json",
    "/var/lib/dynatrace/enrichment/dt_metadata.json",
    "/var/lib/dynatrace/enrichment/dt_host_metadata.json",
]
_PREFLIGHT_TIMEOUT_SECONDS = 5
_logger = logging.getLogger("dynatrace_otel_samples.telemetry")


def _configure_logging() -> None:
    if logging.getLogger().handlers:
        return

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )


def _load_dynatrace_metadata() -> dict[str, str]:
    merged: dict[str, str] = {}
    for name in _METADATA_FILES:
        try:
            if name.startswith("/var"):
                with open(name, "r", encoding="utf-8") as handle:
                    merged.update(json.load(handle))
            else:
                with open(name, "r", encoding="utf-8") as handle:
                    metadata_path = handle.read().strip()

                with open(metadata_path, "r", encoding="utf-8") as metadata_file:
                    merged.update(json.load(metadata_file))
        except Exception:
            continue
    return merged


def _build_resource(service_name: str, service_version: str) -> Resource:
    attributes = _load_dynatrace_metadata()
    attributes.update(
        {
            "service.name": service_name,
            "service.version": service_version,
        }
    )
    return Resource.create(attributes)


def _truncate_error_body(body: str, limit: int = 200) -> str:
    normalized = " ".join(body.split())
    if not normalized:
        return ""
    if len(normalized) <= limit:
        return normalized
    return f"{normalized[:limit]}..."


def _otlp_auth_headers(dt_api_token: str) -> dict[str, str]:
    return {
        "Authorization": f"Api-Token {dt_api_token}",
        "Content-Type": "application/x-protobuf",
    }


def _validate_otlp_connection(endpoint: str, dt_api_token: str) -> None:
    payload = ExportTraceServiceRequest().SerializeToString()

    try:
        response = requests.post(
            endpoint,
            data=payload,
            headers=_otlp_auth_headers(dt_api_token),
            timeout=_PREFLIGHT_TIMEOUT_SECONDS,
        )
    except requests.RequestException as exc:
        raise RuntimeError(
            f"Failed to reach Dynatrace OTLP endpoint {endpoint}: {exc}"
        ) from exc

    if response.status_code in {200, 202}:
        return

    detail = _truncate_error_body(response.text)
    if response.status_code in {401, 403}:
        message = "Dynatrace rejected DT_API_TOKEN for the OTLP traces endpoint."
    elif response.status_code == 404:
        message = (
            "Dynatrace OTLP traces endpoint was not found. "
            "Check that DT_API_URL ends with /api/v2/otlp."
        )
    else:
        message = (
            f"Dynatrace OTLP preflight failed with HTTP {response.status_code}."
        )

    if detail:
        message = f"{message} Response: {detail}"
    raise RuntimeError(message)


class LoggingOTLPSpanExporter(OTLPSpanExporter):
    def __init__(self, service_name: str, **kwargs):
        super().__init__(**kwargs)
        self._service_name = service_name

    def export(self, spans: Sequence[ReadableSpan]) -> SpanExportResult:
        result = super().export(spans)
        if result is SpanExportResult.SUCCESS:
            _logger.info(
                "Exported %s span(s) to Dynatrace for service=%s endpoint=%s",
                len(spans),
                self._service_name,
                self._endpoint,
            )
        else:
            _logger.warning(
                "Failed to export %s span(s) to Dynatrace for service=%s endpoint=%s result=%s",
                len(spans),
                self._service_name,
                self._endpoint,
                result.name,
            )
        return result


def configure_telemetry(service_name: str, service_version: str) -> None:
    _configure_logging()

    dt_api_url = os.environ["DT_API_URL"].rstrip("/")
    dt_api_token = os.environ["DT_API_TOKEN"]
    traces_endpoint = f"{dt_api_url}/v1/traces"

    _validate_otlp_connection(traces_endpoint, dt_api_token)
    _logger.info(
        "Dynatrace OTLP preflight succeeded for service=%s endpoint=%s",
        service_name,
        traces_endpoint,
    )

    provider = TracerProvider(
        resource=_build_resource(service_name, service_version),
        sampler=sampling.ALWAYS_ON,
    )
    provider.add_span_processor(
        BatchSpanProcessor(
            LoggingOTLPSpanExporter(
                service_name=service_name,
                endpoint=traces_endpoint,
                headers={"Authorization": f"Api-Token {dt_api_token}"},
            ),
            schedule_delay_millis=1000,
            export_timeout_millis=5000,
        )
    )

    set_tracer_provider(provider)
    atexit.register(provider.shutdown)


def get_tracer(name: str):
    return trace.get_tracer(name)


def extract_context(headers: Mapping[str, str]):
    carrier = {}
    traceparent = headers.get("traceparent")
    tracestate = headers.get("tracestate")

    if traceparent:
        carrier["traceparent"] = traceparent
    if tracestate:
        carrier["tracestate"] = tracestate

    return TraceContextTextMapPropagator().extract(carrier)


def inject_context(headers: dict[str, str]) -> dict[str, str]:
    inject(headers)
    return headers
