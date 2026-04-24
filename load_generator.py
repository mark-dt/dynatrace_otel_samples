import argparse
import concurrent.futures
import itertools
import threading
import time

import requests


def parse_args():
    parser = argparse.ArgumentParser(description="Generate load for the Dynatrace sample frontend service.")
    parser.add_argument("--url", default="http://127.0.0.1:8000/demo", help="Base frontend URL without the item id suffix.")
    parser.add_argument(
        "--seconds",
        type=int,
        default=60,
        help="How long to keep generating traffic. Use 0 to run until interrupted.",
    )
    parser.add_argument("--requests-per-second", type=int, default=2, help="How many requests to send per second.")
    parser.add_argument("--concurrency", type=int, default=2, help="Number of concurrent workers.")
    parser.add_argument("--timeout", type=float, default=5.0, help="Per-request timeout in seconds.")
    parser.add_argument("--item-prefix", default="widget", help="Prefix for generated item ids.")
    return parser.parse_args()


def main():
    args = parse_args()
    started_at = time.perf_counter()
    latencies = []
    successes = 0
    failures = 0
    lock = threading.Lock()
    counter = itertools.count(1)

    def send_one():
        nonlocal successes, failures

        item_id = f"{args.item_prefix}-{next(counter)}"
        url = f"{args.url.rstrip('/')}/{item_id}"
        request_started = time.perf_counter()

        try:
            response = requests.get(url, timeout=args.timeout)
            latency_ms = (time.perf_counter() - request_started) * 1000

            with lock:
                latencies.append(latency_ms)
                if response.ok:
                    successes += 1
                else:
                    failures += 1
        except Exception:
            with lock:
                failures += 1

    total_requests = 0
    total_waves = itertools.count() if args.seconds == 0 else range(args.seconds)

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.concurrency)) as executor:
        try:
            for second in total_waves:
                wave_started = time.perf_counter()
                futures = [executor.submit(send_one) for _ in range(args.requests_per_second)]
                for future in concurrent.futures.as_completed(futures):
                    future.result()
                total_requests += args.requests_per_second

                elapsed_in_wave = time.perf_counter() - wave_started
                if (args.seconds == 0 or second < args.seconds - 1) and elapsed_in_wave < 1.0:
                    time.sleep(1.0 - elapsed_in_wave)
        except KeyboardInterrupt:
            pass

    elapsed = time.perf_counter() - started_at
    p95_ms = 0.0
    avg_ms = 0.0
    if latencies:
        sorted_latencies = sorted(latencies)
        avg_ms = sum(sorted_latencies) / len(sorted_latencies)
        index = min(len(sorted_latencies) - 1, max(0, int(len(sorted_latencies) * 0.95) - 1))
        p95_ms = sorted_latencies[index]

    print(f"Target URL: {args.url}")
    print("Seconds: continuous" if args.seconds == 0 else f"Seconds: {args.seconds}")
    print(f"Requests per second: {args.requests_per_second}")
    print(f"Approximate spans per second: {args.requests_per_second * 2}")
    print(f"Total requests: {total_requests}")
    print(f"Concurrency: {args.concurrency}")
    print(f"Successes: {successes}")
    print(f"Failures: {failures}")
    print(f"Duration: {elapsed:.2f}s")
    print(f"Throughput: {total_requests / elapsed:.2f} req/s" if elapsed > 0 else "Throughput: n/a")
    print(f"Average latency: {avg_ms:.2f} ms")
    print(f"P95 latency: {p95_ms:.2f} ms")


if __name__ == "__main__":
    main()
