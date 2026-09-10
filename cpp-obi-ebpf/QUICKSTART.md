# Monitor any application with OBI — in 5 steps

Zero code changes. No restart of your app. Linux only.

You need: a Linux host with a BTF-enabled kernel, root, and a Dynatrace API
token with `openTelemetryTrace.ingest` and `metrics.ingest`.

Kernel 5.8+ is necessary but not sufficient: OBI needs BTF, and a kernel built
without `CONFIG_DEBUG_INFO_BTF` cannot load the probes. Check first —

```bash
uname -r                        # 5.8 or newer
ls /sys/kernel/btf/vmlinux      # must exist
```

Debian 12, Ubuntu 22.04+, RHEL 9 and Amazon Linux 2023 all ship BTF.

---

## 1. Download OBI

```bash
curl -fL -o obi.tar.gz \
  https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/releases/download/v0.12.2/obi-v0.12.2-linux-amd64.tar.gz
tar -xzf obi.tar.gz obi
```

(Use `arm64` instead of `amd64` on ARM.)

## 2. Find your application's binary

`exe_path` in the next step needs the *resolved* path of the running binary,
which is not always what the command line shows — a wrapper script, a relative
path or a symlink all print something else:

```bash
sudo readlink -f /proc/$(pgrep -n myapp)/exe
```

Note the full path, e.g. `/usr/local/bin/myapp`. Getting this wrong is the most
common reason nothing turns up later.

## 3. Write `obi-config.yaml`

Replace the binary path and your environment ID — `ENVID` appears twice.

```yaml
discovery:
  instrument:
    - exe_path: /usr/local/bin/myapp
      name: myapp

# Lets OBI inject and read the traceparent header itself, so calls between two
# instrumented processes land in one trace instead of two. Harmless with a
# single application.
ebpf:
  context_propagation: all

otel_traces_export:
  endpoint: https://ENVID.live.dynatrace.com/api/v2/otlp/v1/traces
  protocol: http/protobuf

otel_metrics_export:
  endpoint: https://ENVID.live.dynatrace.com/api/v2/otlp/v1/metrics
  protocol: http/protobuf
  # OBI's default is 60s, so the first metrics arrive a full minute after start.
  interval: 30s
  features:
    - application
```

Keep the `/v1/traces` and `/v1/metrics` on the end — OBI does not add them for you.

On a non-production SaaS tenant, replace `live.dynatrace.com` with your own
domain; on Managed the base URL is `https://<server>/e/ENVID/api/v2/otlp`.

## 4. Run OBI

```bash
sudo mkdir -p /var/cache/obi

sudo XDG_CACHE_HOME=/var/cache/obi \
  OTEL_EXPORTER_OTLP_HEADERS="Authorization=Api-Token dt0c01.XXXX" \
  OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=delta \
  ./obi -config obi-config.yaml
```

Look for this line:

```
msg="instrumenting process" cmd=/usr/local/bin/myapp service=myapp
```

If it appears, you are done. It is also the only proof that your config was
understood: OBI accepts unknown keys in silence, so a misspelled setting looks
exactly like a working one.

OBI runs in the foreground. Leave it running and open a second terminal for the
last step.

## 5. Send some traffic and check Dynatrace

Hit your app a few times, wait about two minutes — one metrics interval plus
ingest — then open **Services** in Dynatrace and look for `myapp`. You get
response time, throughput, failure rate and distributed traces.

---

## If nothing shows up

| Symptom | Fix |
|---|---|
| No `instrumenting process` line | `exe_path` is wrong — must be the exact absolute path from step 2 |
| Line appears, but no data in Dynatrace | Grep OBI's output for `failed to upload` / `failed to send`. It logs export errors at `level=INFO`, so filtering on WARN and ERROR shows a healthy log while nothing is leaving the host. A 404 means the endpoint is missing `/v1/traces` or `/v1/metrics`; a 401 means the token or its scopes are wrong. |
| OBI exits immediately | Not root, no BTF (`/sys/kernel/btf/vmlinux`), or another OBI is already running |

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
