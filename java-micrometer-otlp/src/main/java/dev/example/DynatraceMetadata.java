package dev.example;

import java.io.BufferedReader;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.Reader;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Reads the OneAgent enrichment files and exposes them as OTLP resource attributes, so Dynatrace
 * can attach the exported metrics to the host and process group instance that produced them.
 *
 * <p>See <a href=
 * "https://docs.dynatrace.com/docs/ingest-from/opentelemetry/walkthroughs/java/java-manual#instrument-your-application">
 * Dynatrace: instrument your application</a>. Mirrors python-otel-full/otel_setup.py
 * ({@code _load_dynatrace_enrichment}), which reads the JSON flavour of the same files.
 */
final class DynatraceMetadata {

  private static final Logger log = LoggerFactory.getLogger("dt-metadata");

  /**
   * Spring Boot 4 feeds this map into the Micrometer OTLP resource (via
   * {@code OtlpMetricsPropertiesConfigAdapter#resourceAttributes}) and into the OTel SDK
   * {@code Resource} bean, so one property covers metrics as well as traces and logs.
   */
  private static final String RESOURCE_ATTRIBUTE_PREFIX =
      "management.opentelemetry.resource-attributes.";

  /**
   * Indirection file: it looks like a file in the process working directory, and its single line
   * holds the path of the per-process properties file OneAgent actually wrote.
   */
  private static final String INDIRECTION_FILE =
      "dt_metadata_e617c525669e072eebe3d0f08212e8f2.properties";

  private static final List<String> METADATA_FILES = List.of(
      "/var/lib/dynatrace/enrichment/dt_metadata.properties",
      "/var/lib/dynatrace/enrichment/dt_host_metadata.properties");

  private DynatraceMetadata() {
  }

  /** Merged OneAgent metadata, later files winning. Empty when no OneAgent is present. */
  static Map<String, String> read() {
    Map<String, String> merged = new LinkedHashMap<>();
    readInto(merged, resolveIndirection());
    for (String file : METADATA_FILES) {
      readInto(merged, file);
    }
    return merged;
  }

  /** The metadata as Spring properties, ready to hand to {@code SpringApplicationBuilder}. */
  static Map<String, Object> asSpringProperties() {
    Map<String, String> metadata = read();
    if (metadata.isEmpty()) {
      log.info("No OneAgent metadata found - exporting without Dynatrace topology enrichment");
      return Map.of();
    }
    Map<String, Object> properties = new LinkedHashMap<>();
    // Brackets keep a dotted key such as dt.entity.host as one map key instead of nested levels.
    metadata.forEach((key, value) ->
        properties.put(RESOURCE_ATTRIBUTE_PREFIX + "[" + key + "]", value));
    log.info("OneAgent metadata enrichment: {}", metadata);
    return properties;
  }

  private static String resolveIndirection() {
    try (BufferedReader reader =
        new BufferedReader(new FileReader(INDIRECTION_FILE, StandardCharsets.UTF_8))) {
      String path = reader.readLine();
      return (path == null || path.isBlank()) ? null : path.trim();
    } catch (IOException ex) {
      // No OneAgent on this machine - a normal state for the sample.
      return null;
    }
  }

  /**
   * Neither the indirection file nor the per-process file it points at is a real file on disk:
   * OneAgent materialises both by hooking {@code open()}. It does not hook {@code stat()}, so
   * {@code Files.exists}/{@code Files.isReadable} report {@code false} for them. Never guard these
   * reads with an existence check - just open and let the failure be the signal.
   */
  private static void readInto(Map<String, String> target, String file) {
    if (file == null) {
      return;
    }
    Properties properties = new Properties();
    try (Reader reader = new InputStreamReader(new FileInputStream(file), StandardCharsets.UTF_8)) {
      properties.load(reader);
    } catch (FileNotFoundException ex) {
      return;
    } catch (IOException ex) {
      log.warn("Could not read OneAgent metadata file {}: {}", file, ex.getMessage());
      return;
    }
    properties.forEach((key, value) -> target.put(key.toString(), value.toString()));
  }
}
