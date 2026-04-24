import argparse
import json
import os
import random
import socket
import sys
import time
from datetime import datetime, timezone

import requests


DEFAULT_SOURCE = "python-dummy-log-generator"
DEFAULT_LOG_LEVELS = ("INFO", "WARN", "ERROR")
DEFAULT_TIMEOUT_SECONDS = 10
MAX_AIR_ID_VALUES = 10


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Send dummy logs to Dynatrace. Each log contains an air_id field "
            "chosen from a pool of up to 10 distinct 4-digit values."
        )
    )
    parser.add_argument(
        "--count",
        type=int,
        default=20,
        help="Number of log records to send. Default: 20",
    )
    parser.add_argument(
        "--air-id-count",
        type=int,
        default=10,
        help="How many distinct 4-digit air_id values to generate. Max: 10",
    )
    parser.add_argument(
        "--endpoint",
        default=os.getenv("DT_LOG_INGEST_URL"),
        help=(
            "Dynatrace log ingest endpoint, for example "
            "https://<env>.live.dynatrace.com/api/v2/logs/ingest. "
            "Defaults to DT_LOG_INGEST_URL."
        ),
    )
    parser.add_argument(
        "--token",
        default=os.getenv("DT_API_TOKEN"),
        help="Dynatrace API token. Defaults to DT_API_TOKEN.",
    )
    parser.add_argument(
        "--source",
        default=DEFAULT_SOURCE,
        help=f"Value for the log source field. Default: {DEFAULT_SOURCE}",
    )
    parser.add_argument(
        "--interval-seconds",
        type=float,
        default=0.0,
        help="Delay between sent logs. Default: 0",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the payload instead of sending it to Dynatrace.",
    )
    args = parser.parse_args()

    if args.count < 1:
        parser.error("--count must be at least 1.")
    if not 1 <= args.air_id_count <= MAX_AIR_ID_VALUES:
        parser.error("--air-id-count must be between 1 and 10.")
    if not args.dry_run and not args.endpoint:
        parser.error("--endpoint is required unless --dry-run is used.")
    if not args.dry_run and not args.token:
        parser.error("--token is required unless --dry-run is used.")

    return args


def build_air_ids(count: int) -> list[str]:
    values = set()
    while len(values) < count:
        values.add(f"{random.randint(0, 9999):04d}")
    return sorted(values)


def build_log_record(index: int, air_ids: list[str], source: str) -> dict[str, object]:
    air_id = random.choice(air_ids)
    return {
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
        "severity": random.choice(DEFAULT_LOG_LEVELS),
        "content": f"Dummy booking log {index + 1} for air_id={air_id}",
        "air_id": air_id,
        "source": source,
        "log.source": source,
        "host": socket.gethostname(),
        "event.type": "dummy.air.booking",
        "status": random.choice(("created", "updated", "confirmed")),
        "sequence": index + 1,
    }


def send_log(endpoint: str, token: str, log_record: dict[str, object]) -> requests.Response:
    return requests.post(
        endpoint,
        headers={
            "Authorization": f"Api-Token {token}",
            "Content-Type": "application/json; charset=utf-8",
        },
        data=json.dumps(log_record),
        timeout=DEFAULT_TIMEOUT_SECONDS,
    )


def main() -> int:
    args = parse_args()
    air_ids = build_air_ids(args.air_id_count)

    print(f"Generated {len(air_ids)} distinct air_id values: {', '.join(air_ids)}")

    for index in range(args.count):
        log_record = build_log_record(index=index, air_ids=air_ids, source=args.source)

        if args.dry_run:
            print(json.dumps(log_record))
        else:
            response = send_log(args.endpoint, args.token, log_record)
            if response.status_code not in {200, 202, 204}:
                body = " ".join(response.text.split())
                print(
                    f"Failed to send log {index + 1}: HTTP {response.status_code} {body}",
                    file=sys.stderr,
                )
                return 1
            print(
                f"Sent log {index + 1}/{args.count} with air_id={log_record['air_id']}"
            )

        if args.interval_seconds > 0 and index < args.count - 1:
            time.sleep(args.interval_seconds)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
