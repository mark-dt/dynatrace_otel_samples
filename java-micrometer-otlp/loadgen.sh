#!/usr/bin/env bash
# Usage: ./loadgen.sh <url> <duration_sec> <concurrency> <rps>
# Defaults: url=http://localhost:8080/hello duration=60 concurrency=4 rps=40

set -u
URL="${1:-http://localhost:8080/hello}"
DURATION="${2:-60}"         # seconds
CONCURRENCY="${3:-4}"
RPS="${4:-40}"

# ceil(RPS / CONCURRENCY)
per_thread_rps=$(( (RPS + CONCURRENCY - 1) / CONCURRENCY ))
end=$(( $(date +%s) + DURATION ))

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

worker() {
  local out="$1"
  local ok=0 ko=0
  # interval seconds between requests for this worker
  local interval
  if [ "$per_thread_rps" -gt 0 ]; then
    interval=$(awk "BEGIN { printf \"%.6f\", 1/$per_thread_rps }")
  else
    interval="1"
  fi

  while [ "$(date +%s)" -lt "$end" ]; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$URL" || echo "000")
    if [ "$code" = "200" ]; then ok=$((ok+1)); else ko=$((ko+1)); fi
    sleep "$interval"
  done
  printf "%d %d\n" "$ok" "$ko" > "$out"
}

for i in $(seq 1 "$CONCURRENCY"); do
  worker "$tmpdir/$i" &
done
wait

success=0; fail=0
for f in "$tmpdir"/*; do
  read ok ko < "$f"
  success=$((success+ok)); fail=$((fail+ko))
done

total=$((success+fail))
echo "URL:          $URL"
echo "Duration:     ${DURATION}s"
echo "Concurrency:  $CONCURRENCY"
echo "Target RPS:   $RPS (≈ $((per_thread_rps*CONCURRENCY)) actual)"
echo "Requests:     $total"
echo "2xx:          $success"
echo "Non-2xx:      $fail"
