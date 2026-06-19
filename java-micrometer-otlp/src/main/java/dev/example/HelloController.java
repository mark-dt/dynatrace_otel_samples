package dev.example;

import io.micrometer.core.annotation.Timed;
import io.micrometer.core.instrument.Counter;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
class HelloController {

  private final Counter counter;

  HelloController(Counter counter) {
    this.counter = counter;
  }

  @Timed(value = "demo.hello.timer", description = "Timer for /hello")
  @GetMapping("/hello")
  String hello() {
    counter.increment(); // emit a data point
    return "hi from spring-otlp-demo\n";
  }
}

