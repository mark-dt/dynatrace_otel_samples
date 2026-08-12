package dev.example;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.context.annotation.Bean;

@SpringBootApplication
public class DemoApplication {

  public static void main(String[] args) {
    // The OneAgent metadata has to be in the Environment before the OTLP registry is built,
    // so read it here rather than from a bean.
    new SpringApplicationBuilder(DemoApplication.class)
        .properties(DynatraceMetadata.asSpringProperties())
        .run(args);
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
