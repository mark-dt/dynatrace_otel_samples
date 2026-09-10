# Monitor any application with OBI — in 5 steps

Zero code changes. No restart of your app. Linux only.

You need: a Linux host (kernel 5.8+), root, and a Dynatrace API token with
`openTelemetryTrace.ingest` and `metrics.ingest`.

---

## 1. Download OBI

```bash
curl -fL -o obi.tar.gz \
  https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/releases/download/v0.12.2/obi-v0.12.2-linux-amd64.tar.gz
tar -xzf obi.tar.gz obi
```

(Use `arm64` instead of `amd64` on ARM.)

## 2. Find your application's binary

```bash
pgrep -a myapp
```

Note the full path, e.g. `/usr/local/bin/myapp`.

## 3. Write `obi-config.yaml`

Replace the two placeholders — the binary path and your environment ID.

```yaml
discovery:
  instrument:
    - exe_path: /usr/local/bin/myapp
      name: myapp

ebpf:
  context_propagation: all

otel_traces_export:
  endpoint: https://ENVID.live.dynatrace.com/api/v2/otlp/v1/traces
  protocol: http/protobuf

otel_metrics_export:
  endpoint: https://ENVID.live.dynatrace.com/api/v2/otlp/v1/metrics
  protocol: http/protobuf
  features:
    - application
```

Keep the `/v1/traces` and `/v1/metrics` on the end — OBI does not add them for you.

## 4. Run OBI

```bash
sudo XDG_CACHE_HOME=/var/cache/obi \
  OTEL_EXPORTER_OTLP_HEADERS="Authorization=Api-Token dt0c01.XXXX" \
  OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=delta \
  ./obi -config obi-config.yaml
```

Look for this line:

```
msg="instrumenting process" cmd=/usr/local/bin/myapp service=myapp
```

If it appears, you are done. Leave OBI running.

## 5. Send some traffic and check Dynatrace

Hit your app a few times, wait ~1 minute, then open **Services** in Dynatrace
and look for `myapp`. You get response time, throughput, failure rate and
distributed traces.

---

## If nothing shows up

| Symptom | Fix |
|---|---|
| No `instrumenting process` line | `exe_path` is wrong — must be the exact absolute path from step 2 |
| Line appears, but no data in Dynatrace | Check the endpoint URLs end in `/v1/traces` and `/v1/metrics`, and the token is valid |
| OBI exits immediately | Not root, or another OBI is already running |

To check whether OBI is producing data at all, add this to the config and restart it:

```yaml
prometheus_export:
  port: 8999
  path: /metrics
```

```bash
curl -s http://127.0.0.1:8999/metrics | grep myapp
```

Data here but not in Dynatrace means the problem is the export, not the instrumentation.

---

Want a working end-to-end example first? See [README.md](README.md) — two C++
services, a load generator and a `make` target for each step.
