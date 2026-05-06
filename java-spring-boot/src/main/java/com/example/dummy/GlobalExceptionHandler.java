import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.time.Instant;
import java.util.Map;

@RestControllerAdvice
class GlobalExceptionHandler {

  @ExceptionHandler(RuntimeException.class)
  public ResponseEntity<Map<String, Object>> handleRuntime(RuntimeException ex) {
    // For demo purposes: map the injected failure to a controlled response
    if ("service-c injected failure".equals(ex.getMessage())) {
      return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body(Map.of(
          "service", "service-c",
          "status", "error",
          "message", ex.getMessage(),
          "time", Instant.now().toString()
      ));
    }

    // Everything else as generic 500
    return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(Map.of(
        "status", "error",
        "message", ex.getMessage(),
        "time", Instant.now().toString()
    ));
  }
}
