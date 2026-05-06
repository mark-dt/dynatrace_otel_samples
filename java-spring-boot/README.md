# Java Spring Boot Dummy Microservice

A single-process Spring Boot application with three simulated service endpoints and a load generator.

## Endpoints

| Endpoint | Behavior |
|----------|----------|
| `/service-a/hello` | Returns a greeting with 20-120ms simulated latency |
| `/service-b/compute?n=25000` | CPU-bound sum-of-squares computation |
| `/service-c/flaky?errorRate=0.05` | Returns HTTP 503 at the configured error rate |
| `/health` | Health check |

## Setup

```bash
cp .env.example .env
# Edit .env (set DT_TAGS, SERVER_PORT)

mvn package -DskipTests
./run-java.sh
```

## Load generator

```bash
./load.sh [base_url] [duration_sec] [concurrency]
```
