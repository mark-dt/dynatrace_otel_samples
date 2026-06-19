package dev.example;

import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@EnableScheduling
@Component
class AutoEmit {

  private final MeterRegistry registry;

  AutoEmit(MeterRegistry registry) {
    this.registry = registry;
    // one example gauge that changes over time
    registry.gauge("demo.random.gauge", this, self -> Math.random() * 100.0);
  }

  @Scheduled(fixedRate = 5000)
  void tick() {
    // touching a built-in meter ensures there’s always some traffic
    registry.counter("demo.background.counter").increment();
  }
}
