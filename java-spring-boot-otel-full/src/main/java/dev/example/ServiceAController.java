package dev.example;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import io.micrometer.observation.ObservationRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.TimeUnit;

/**
 * Entry-point service. {@code /trigger} calls service B's {@code /store} and
 * {@code /data}. Mirrors python-otel-full/service_a.py.
 */
@RestController
@Profile("service-a")
class ServiceAController {

  private static final Logger log = LoggerFactory.getLogger("service-a");

  private final RestClient restClient;
  private final String serviceBUrl;
  private final Counter triggerRequests;
  private final Counter serviceBCalls;
  private final Timer triggerLatency;

  ServiceAController(ObservationRegistry observationRegistry,
                     MeterRegistry registry,
                     @Value("${SERVICE_B_URL:http://localhost:8081}") String serviceBUrl) {
    // Building from the ObservationRegistry gives an instrumented client: each
    // call produces a client span and propagates the W3C trace context to B.
    this.restClient = RestClient.builder().observationRegistry(observationRegistry).build();
    this.serviceBUrl = serviceBUrl;
    this.triggerRequests = Counter.builder("service_a_trigger_requests_total")
        .description("Number of /trigger calls").register(registry);
    this.serviceBCalls = Counter.builder("service_a_service_b_calls_total")
        .description("Outbound calls from A to B").register(registry);
    this.triggerLatency = Timer.builder("service_a_trigger_latency_ms")
        .description("Latency of /trigger handler").register(registry);
  }

  @GetMapping("/health")
  Map<String, String> health() {
    return Map.of("status", "ok");
  }

  @GetMapping("/trigger")
  Map<String, Object> trigger() {
    long start = System.nanoTime();
    log.info("Trigger called");
    triggerRequests.increment();

    Map<String, String> payload = Map.of("message", "Hello from Service A!");

    serviceBCalls.increment();
    var storeResp = restClient.post()
        .uri(serviceBUrl + "/store")
        .contentType(MediaType.APPLICATION_JSON)
        .body(payload)
        .retrieve()
        .toBodilessEntity();
    log.info("POST /store status={}", storeResp.getStatusCode().value());

    serviceBCalls.increment();
    var dataResp = restClient.get()
        .uri(serviceBUrl + "/data")
        .retrieve()
        .toBodilessEntity();
    log.info("GET /data status={}", dataResp.getStatusCode().value());

    long elapsedNanos = System.nanoTime() - start;
    triggerLatency.record(elapsedNanos, TimeUnit.NANOSECONDS);

    double elapsedMs = elapsedNanos / 1_000_000.0;
    Map<String, Object> resp = new LinkedHashMap<>();
    resp.put("status", "ok");
    resp.put("latency_ms", Math.round(elapsedMs * 100.0) / 100.0);
    return resp;
  }
}
