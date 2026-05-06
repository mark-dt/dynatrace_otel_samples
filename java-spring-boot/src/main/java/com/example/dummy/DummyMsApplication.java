package com.example.dummy;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;

@SpringBootApplication
public class DummyMsApplication {
  public static void main(String[] args) {
    SpringApplication.run(DummyMsApplication.class, args);
  }
}

@RestController
@RequestMapping(produces = MediaType.APPLICATION_JSON_VALUE)
class DummyController {

  // Read DT_TAGS from the environment (Dynatrace convention).
  private final String dtTags = System.getenv().getOrDefault("DT_TAGS", "");

  @GetMapping("/service-a/hello")
  public Map<String, Object> serviceA() throws InterruptedException {
    // Simulate small variable latency
    Thread.sleep(ThreadLocalRandom.current().nextInt(20, 120));
    return Map.of(
        "service", "service-a",
        "message", "hello",
        "time", Instant.now().toString(),
        "dt_tags", dtTags
    );
  }

  @GetMapping("/service-b/compute")
  public Map<String, Object> serviceB(@RequestParam(defaultValue = "25000") int n) {
    // Burn a little CPU deterministically
    long sum = 0;
    for (int i = 1; i <= n; i++) sum += (long) i * i;

    return Map.of(
        "service", "service-b",
        "operation", "sumSquares",
        "n", n,
        "result", sum,
        "dt_tags", dtTags
    );
  }

  @GetMapping("/service-c/flaky")
  public ResponseEntity<Map<String, Object>> serviceC(@RequestParam(defaultValue = "0.05") double errorRate) {
    // Sometimes return an error to create interesting traces — without throwing exceptions (no stacktrace spam)
    double r = ThreadLocalRandom.current().nextDouble();
    if (r < errorRate) {
      return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body(Map.of(
          "service", "service-c",
          "status", "error",
          "message", "service-c injected failure",
          "errorRate", errorRate,
          "dt_tags", dtTags
      ));
    }

    return ResponseEntity.ok(Map.of(
        "service", "service-c",
        "status", "ok",
        "errorRate", errorRate,
        "dt_tags", dtTags
    ));
  }

  @GetMapping("/health")
  public Map<String, Object> health() {
    return Map.of("status", "UP", "time", Instant.now().toString());
  }

  // Handy endpoint to verify what the process sees
  @GetMapping("/env")
  public Map<String, Object> env() {
    return Map.of(
        "DT_TAGS", dtTags,
        "JAVA_VERSION", System.getProperty("java.version")
    );
  }
}
