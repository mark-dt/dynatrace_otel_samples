package dev.example;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Backend store service. Exposes {@code /store} and {@code /data}.
 * Mirrors python-otel-full/service_b.py.
 */
@RestController
@Profile("service-b")
class ServiceBController {

  private static final Logger log = LoggerFactory.getLogger("service-b");

  private final List<Object> store = new CopyOnWriteArrayList<>();
  private final AtomicInteger itemCount = new AtomicInteger(0);
  private final Counter storeRequests;
  private final Counter dataRequests;
  private final Timer storeLatency;

  ServiceBController(MeterRegistry registry) {
    this.storeRequests = Counter.builder("service_b_store_requests_total")
        .description("Number of /store calls").register(registry);
    this.dataRequests = Counter.builder("service_b_data_requests_total")
        .description("Number of /data calls").register(registry);
    this.storeLatency = Timer.builder("service_b_store_latency_ms")
        .description("Latency of /store handler").register(registry);
    // Gauge reflecting the current number of stored items.
    registry.gauge("service_b_items_stored", itemCount);
  }

  @GetMapping("/health")
  Map<String, String> health() {
    return Map.of("status", "ok");
  }

  @PostMapping("/store")
  Map<String, Object> store(@RequestBody(required = false) Map<String, Object> body) {
    long start = System.nanoTime();
    store.add(body == null ? Map.of() : body);
    itemCount.set(store.size());
    storeRequests.increment();
    log.info("stored item count={}", store.size());
    storeLatency.record(System.nanoTime() - start, TimeUnit.NANOSECONDS);
    return Map.of("stored", true, "count", store.size());
  }

  @GetMapping("/data")
  Map<String, Object> data() {
    dataRequests.increment();
    log.info("returning item count={}", store.size());
    return Map.of("items", store);
  }
}
