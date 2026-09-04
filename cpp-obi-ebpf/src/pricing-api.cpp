// pricing-api - a deliberately plain C++17 HTTP/1.1 server.
//
// No OpenTelemetry SDK, no tracing library, no HTTP framework: POSIX sockets
// and one thread per connection. OBI instruments it from the outside with
// eBPF, so this file contains nothing observability-related on purpose. Search
// it for "otel" or "trace" and you will find only these comments.
//
//   GET /price?item=widget&qty=3  -> quote, after calling inventory-api
//   GET /health                   -> ok
//   anything else                 -> 404
//
// It calls inventory-api on every /price request so that OBI produces a
// two-span trace (server span -> client span) rather than a lone request.
//
// Environment:
//   PRICING_PORT     listen port            (default 8083)
//   INVENTORY_HOST   downstream host        (default 127.0.0.1)
//   INVENTORY_PORT   downstream port        (default 8082)

#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <random>
#include <string>
#include <thread>

namespace {

constexpr size_t kMaxRequest = 64 * 1024;

// Read once at startup. Configurable so the sample can be rearranged without
// editing code - OBI discovers the process by executable path, not by port, so
// changing these does not require touching the OBI config.
int envInt(const char *name, int fallback) {
  const char *v = std::getenv(name);
  return (v && *v) ? std::atoi(v) : fallback;
}

std::string envStr(const char *name, const char *fallback) {
  const char *v = std::getenv(name);
  return (v && *v) ? std::string(v) : std::string(fallback);
}

const int         kListenPort    = envInt("PRICING_PORT", 8083);
const std::string kInventoryHost = envStr("INVENTORY_HOST", "127.0.0.1");
const int         kInventoryPort = envInt("INVENTORY_PORT", 8082);

// Per-thread RNG. rand() is not thread safe and a shared engine would need a
// lock on every request.
thread_local std::mt19937 rng{std::random_device{}()};

int randInt(int lo, int hi) {
  return std::uniform_int_distribution<int>(lo, hi)(rng);
}

// ---------- tiny HTTP helpers ----------

// Read until the end of the header block. These are small requests with no
// body, so the headers are the whole message.
bool readRequest(int fd, std::string &out) {
  char buf[4096];
  out.clear();
  while (out.find("\r\n\r\n") == std::string::npos) {
    ssize_t n = ::recv(fd, buf, sizeof(buf), 0);
    if (n <= 0) return false;
    out.append(buf, static_cast<size_t>(n));
    if (out.size() > kMaxRequest) return false;
  }
  return true;
}

bool writeAll(int fd, const std::string &data) {
  size_t sent = 0;
  while (sent < data.size()) {
    ssize_t n = ::send(fd, data.data() + sent, data.size() - sent, MSG_NOSIGNAL);
    if (n <= 0) return false;
    sent += static_cast<size_t>(n);
  }
  return true;
}

std::string reasonPhrase(int status) {
  switch (status) {
    case 200: return "OK";
    case 404: return "Not Found";
    case 409: return "Conflict";
    case 500: return "Internal Server Error";
    case 502: return "Bad Gateway";
    default:  return "Unknown";
  }
}

// A complete HTTP/1.1 response with Content-Length, so OBI sees a clean
// request/response pair and the connection can be closed deterministically.
std::string buildResponse(int status, const std::string &contentType,
                          const std::string &body) {
  std::string out;
  out.reserve(body.size() + 160);
  out += "HTTP/1.1 " + std::to_string(status) + " " + reasonPhrase(status) + "\r\n";
  out += "Content-Type: " + contentType + "\r\n";
  out += "Content-Length: " + std::to_string(body.size()) + "\r\n";
  out += "Connection: close\r\n\r\n";
  out += body;
  return out;
}

// ---------- request line parsing ----------

struct Request {
  std::string method;
  std::string path;
  std::string query;
};

Request parseRequest(const std::string &raw) {
  Request r;
  size_t lineEnd = raw.find("\r\n");
  std::string line = raw.substr(0, lineEnd == std::string::npos ? raw.size() : lineEnd);

  size_t sp1 = line.find(' ');
  if (sp1 == std::string::npos) return r;
  size_t sp2 = line.find(' ', sp1 + 1);
  if (sp2 == std::string::npos) return r;

  r.method = line.substr(0, sp1);
  std::string target = line.substr(sp1 + 1, sp2 - sp1 - 1);

  size_t q = target.find('?');
  if (q == std::string::npos) {
    r.path = target;
  } else {
    r.path = target.substr(0, q);
    r.query = target.substr(q + 1);
  }
  return r;
}

std::string queryParam(const std::string &query, const std::string &key,
                       const std::string &fallback) {
  size_t pos = 0;
  while (pos <= query.size()) {
    size_t amp = query.find('&', pos);
    std::string pair = query.substr(pos, amp == std::string::npos ? std::string::npos : amp - pos);
    size_t eq = pair.find('=');
    if (eq != std::string::npos && pair.substr(0, eq) == key) {
      return pair.substr(eq + 1);
    }
    if (amp == std::string::npos) break;
    pos = amp + 1;
  }
  return fallback;
}

// ---------- outbound call to inventory-api ----------
//
// Hand-rolled so the outbound socket syscalls are as plain as the inbound
// ones. This is what OBI turns into the client span of the trace.

struct HttpResult {
  bool ok = false;
  int status = 0;
  std::string body;
};

HttpResult httpGet(const char *host, int port, const std::string &path) {
  HttpResult result;

  int fd = ::socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0) return result;

  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_port = htons(static_cast<uint16_t>(port));
  if (::inet_pton(AF_INET, host, &addr.sin_addr) != 1) {
    ::close(fd);
    return result;
  }

  timeval tv{};
  tv.tv_sec = 5;
  ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
  ::setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

  if (::connect(fd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) != 0) {
    ::close(fd);
    return result;
  }

  std::string req = "GET " + path + " HTTP/1.1\r\n";
  req += "Host: " + std::string(host) + ":" + std::to_string(port) + "\r\n";
  req += "User-Agent: pricing-api/1.0\r\n";
  req += "Accept: application/json\r\n";
  req += "Connection: close\r\n\r\n";

  if (!writeAll(fd, req)) {
    ::close(fd);
    return result;
  }

  std::string raw;
  char buf[4096];
  ssize_t n;
  while ((n = ::recv(fd, buf, sizeof(buf), 0)) > 0) {
    raw.append(buf, static_cast<size_t>(n));
    if (raw.size() > kMaxRequest) break;
  }
  ::close(fd);

  if (raw.size() < 12 || raw.compare(0, 5, "HTTP/") != 0) return result;
  result.status = std::atoi(raw.c_str() + 9);

  size_t hdrEnd = raw.find("\r\n\r\n");
  result.body = (hdrEnd == std::string::npos) ? "" : raw.substr(hdrEnd + 4);
  result.ok = true;
  return result;
}

// Pull an integer field out of the inventory-api JSON without a JSON library.
// The response shape is fixed and generated by us, so a substring scan is
// enough and keeps the binary dependency-free.
int jsonInt(const std::string &body, const std::string &key, int fallback) {
  std::string needle = "\"" + key + "\":";
  size_t pos = body.find(needle);
  if (pos == std::string::npos) return fallback;
  return std::atoi(body.c_str() + pos + needle.size());
}

// ---------- handlers ----------

std::string handlePrice(const Request &req, int &status) {
  std::string item = queryParam(req.query, "item", "widget");
  int qty = std::atoi(queryParam(req.query, "qty", "1").c_str());
  if (qty <= 0) qty = 1;

  // A small slice of requests fail outright, so the error rate OBI reports is
  // not permanently zero.
  if (randInt(1, 100) <= 6) {
    status = 500;
    std::cout << "[pricing-api] price item=" << item << " qty=" << qty
              << " FAILED pricing_engine_error" << std::endl;
    return "{\"status\":\"error\",\"error\":\"pricing_engine_error\"}";
  }

  std::string path = "/check?item=" + item + "&qty=" + std::to_string(qty);
  HttpResult inv = httpGet(kInventoryHost.c_str(), kInventoryPort, path);

  if (!inv.ok) {
    status = 502;
    std::cout << "[pricing-api] price item=" << item << " qty=" << qty
              << " FAILED inventory_unreachable" << std::endl;
    return "{\"status\":\"error\",\"error\":\"inventory_unreachable\"}";
  }

  int available = jsonInt(inv.body, "available", 0);

  if (inv.status != 200) {
    status = 409;
    std::cout << "[pricing-api] price item=" << item << " qty=" << qty
              << " available=" << available << " REJECTED out_of_stock" << std::endl;
    return "{\"status\":\"rejected\",\"reason\":\"out_of_stock\",\"item\":\"" + item + "\"}";
  }

  // Deterministic-ish pricing: a base per item plus a small spread, minus a
  // bulk discount. The numbers only need to be plausible.
  int unitCents = 450 + static_cast<int>(item.size()) * 25 + randInt(0, 120);
  int discount = (qty >= 4) ? 10 : 0;
  int totalCents = unitCents * qty * (100 - discount) / 100;

  // A little variable work so the latency histogram has a shape.
  std::this_thread::sleep_for(std::chrono::milliseconds(randInt(2, 45)));

  status = 200;
  std::cout << "[pricing-api] price item=" << item << " qty=" << qty
            << " available=" << available << " unit=" << unitCents
            << " total=" << totalCents << " OK" << std::endl;

  return "{\"item\":\"" + item + "\",\"qty\":" + std::to_string(qty) +
         ",\"available\":" + std::to_string(available) +
         ",\"unitCents\":" + std::to_string(unitCents) +
         ",\"discountPct\":" + std::to_string(discount) +
         ",\"totalCents\":" + std::to_string(totalCents) + "}";
}

void handleConnection(int fd) {
  int one = 1;
  ::setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));

  timeval tv{};
  tv.tv_sec = 10;
  ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

  std::string raw;
  if (!readRequest(fd, raw)) {
    ::close(fd);
    return;
  }

  Request req = parseRequest(raw);
  int status = 200;
  std::string body;
  std::string type = "application/json";

  if (req.path == "/health") {
    body = "ok";
    type = "text/plain";
  } else if (req.path == "/price") {
    body = handlePrice(req, status);
  } else {
    status = 404;
    body = "{\"status\":\"error\",\"error\":\"not_found\"}";
    std::cout << "[pricing-api] " << req.method << " " << req.path
              << " -> 404" << std::endl;
  }

  writeAll(fd, buildResponse(status, type, body));
  ::shutdown(fd, SHUT_WR);
  ::close(fd);
}

}  // namespace

int main() {
  // Unbuffered-ish logging: systemd captures stdout, and line buffering would
  // hold log lines back when stdout is a pipe rather than a terminal.
  std::ios::sync_with_stdio(false);
  std::cout.setf(std::ios::unitbuf);

  int listenFd = ::socket(AF_INET, SOCK_STREAM, 0);
  if (listenFd < 0) {
    std::cerr << "[pricing-api] socket() failed: " << std::strerror(errno) << std::endl;
    return 1;
  }

  int one = 1;
  ::setsockopt(listenFd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_ANY);
  addr.sin_port = htons(static_cast<uint16_t>(kListenPort));

  if (::bind(listenFd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) != 0) {
    std::cerr << "[pricing-api] bind() failed: " << std::strerror(errno) << std::endl;
    return 1;
  }
  if (::listen(listenFd, 128) != 0) {
    std::cerr << "[pricing-api] listen() failed: " << std::strerror(errno) << std::endl;
    return 1;
  }

  std::cout << "[pricing-api] listening on " << kListenPort
            << ", downstream inventory-api at " << kInventoryHost << ":"
            << kInventoryPort << std::endl;

  for (;;) {
    int fd = ::accept(listenFd, nullptr, nullptr);
    if (fd < 0) {
      if (errno == EINTR) continue;
      std::cerr << "[pricing-api] accept() failed: " << std::strerror(errno) << std::endl;
      continue;
    }
    // Thread per connection. Plain blocking recv/send on a dedicated thread is
    // the shape OBI's HTTP probes are built around.
    std::thread(handleConnection, fd).detach();
  }
}
