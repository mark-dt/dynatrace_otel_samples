package dev.example;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;

@SpringBootApplication
public class DemoApplication {

  public static void main(String[] args) {
    SpringApplication.run(DemoApplication.class, args);
  }

  @Bean
  Counter demoCounter(MeterRegistry registry) {
    // a simple custom counter that we'll bump from our controller & a scheduler
    return Counter.builder("demo.requests.total")
        .description("Number of demo requests")
        .tag("endpoint", "/hello")
        .register(registry);
  }
}
