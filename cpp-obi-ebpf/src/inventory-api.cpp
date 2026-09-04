// inventory-api - the downstream half of the sample, same plain C++17 style as
// pricing-api: POSIX sockets, one thread per connection, no dependencies.
//
// It exists so pricing-api has something real to call, which is what turns the
// telemetry into a two-span distributed trace instead of a single server span.
//
//   GET /check?item=widget&qty=3  -> {"item":...,"available":N,"inStock":bool}
//                                    200 when in stock, 409 when not
//   GET /health                   -> ok
//   anything else                 -> 404
//
// Environment:
//   INVENTORY_PORT   listen port  (default 8082)

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

// Anything outside this list is unknown stock and always reports zero, so the
// 409 path is reachable on demand rather than only by chance.
const char *kKnownItems[] = {"widget", "gizmo", "sprocket", "flange"};

int envInt(const char *name, int fallback) {
  const char *v = std::getenv(name);
  return (v && *v) ? std::atoi(v) : fallback;
}

const int kListenPort = envInt("INVENTORY_PORT", 8082);

// Per-thread RNG: rand() is not thread safe and a shared engine would need a
// lock on every request.
thread_local std::mt19937 rng{std::random_device{}()};

int randInt(int lo, int hi) {
  return std::uniform_int_distribution<int>(lo, hi)(rng);
}

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
    default:  return "Unknown";
  }
}

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

bool knownItem(const std::string &item) {
  for (const char *k : kKnownItems) {
    if (item == k) return true;
  }
  return false;
}

std::string handleCheck(const Request &req, int &status) {
  std::string item = queryParam(req.query, "item", "widget");
  int qty = std::atoi(queryParam(req.query, "qty", "1").c_str());
  if (qty <= 0) qty = 1;

  int available = knownItem(item) ? randInt(0, 49) : 0;
  bool ok = available >= qty;

  // A slow tail on roughly one call in ten, so the latency histogram OBI
  // reports has a shape instead of a single flat bucket.
  int delayMs = (randInt(1, 100) <= 10) ? randInt(400, 1000) : randInt(0, 40);
  std::this_thread::sleep_for(std::chrono::milliseconds(delayMs));

  status = ok ? 200 : 409;
  std::cout << "[inventory-api] check item=" << item << " qty=" << qty
            << " available=" << available << " ok=" << (ok ? "true" : "false")
            << " delay=" << delayMs << "ms" << std::endl;

  return "{\"item\":\"" + item + "\",\"requested\":" + std::to_string(qty) +
         ",\"available\":" + std::to_string(available) +
         ",\"inStock\":" + (ok ? "true" : "false") + "}";
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
  } else if (req.path == "/check") {
    body = handleCheck(req, status);
  } else {
    status = 404;
    body = "{\"status\":\"error\",\"error\":\"not_found\"}";
    std::cout << "[inventory-api] " << req.method << " " << req.path
              << " -> 404" << std::endl;
  }

  writeAll(fd, buildResponse(status, type, body));
  ::shutdown(fd, SHUT_WR);
  ::close(fd);
}

}  // namespace

int main() {
  std::ios::sync_with_stdio(false);
  std::cout.setf(std::ios::unitbuf);

  int listenFd = ::socket(AF_INET, SOCK_STREAM, 0);
  if (listenFd < 0) {
    std::cerr << "[inventory-api] socket() failed: " << std::strerror(errno) << std::endl;
    return 1;
  }

  int one = 1;
  ::setsockopt(listenFd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_ANY);
  addr.sin_port = htons(static_cast<uint16_t>(kListenPort));

  if (::bind(listenFd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) != 0) {
    std::cerr << "[inventory-api] bind() failed: " << std::strerror(errno) << std::endl;
    return 1;
  }
  if (::listen(listenFd, 128) != 0) {
    std::cerr << "[inventory-api] listen() failed: " << std::strerror(errno) << std::endl;
    return 1;
  }

  std::cout << "[inventory-api] listening on " << kListenPort << std::endl;

  for (;;) {
    int fd = ::accept(listenFd, nullptr, nullptr);
    if (fd < 0) {
      if (errno == EINTR) continue;
      std::cerr << "[inventory-api] accept() failed: " << std::strerror(errno) << std::endl;
      continue;
    }
    std::thread(handleConnection, fd).detach();
  }
}
