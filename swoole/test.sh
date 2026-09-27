#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$ROOT_DIR/results"

DURATION="${DURATION:-30}"
RATE="${RATE:-50}"

mkdir -p "$RESULTS_DIR"

echo "======================================"
echo " REST Runtime Benchmark"
echo "======================================"
echo
echo "Duration : ${DURATION}s"
echo "Rate     : ${RATE} req/s"
echo

# --------------------------------------------------
# Helpers
# --------------------------------------------------

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_artillery() {
    if ! command_exists artillery; then
        echo "ERROR: Artillery is not installed."
        echo
        echo "Install with:"
        echo "  npm install -g artillery@latest"
        exit 1
    fi
}

check_url() {
    local name="$1"
    local url="$2"

    echo "Checking $name..."

    if curl -fsS "$url" >/dev/null; then
        echo "  OK: $url"
    else
        echo "  ERROR: $url is not responding"
        return 1
    fi
}

run_artillery() {
    local name="$1"
    local url="$2"
    local output="$3"

    echo
    echo "--------------------------------------"
    echo " Testing: $name"
    echo " Target : $url"
    echo "--------------------------------------"

    artillery run \
        --target "$url" \
        --output "$output" \
        "$ROOT_DIR/scenarios/rest.yml"
}

# --------------------------------------------------
# Dependencies
# --------------------------------------------------

check_artillery

command_exists curl || {
    echo "ERROR: curl is required."
    exit 1
}

# --------------------------------------------------
# Scenario
# --------------------------------------------------

mkdir -p "$ROOT_DIR/scenarios"

if [ ! -f "$ROOT_DIR/scenarios/rest.yml" ]; then

cat > "$ROOT_DIR/scenarios/rest.yml" <<'EOF'
config:
  phases:
    - duration: 30
      arrivalRate: 50

scenarios:

  - name: "REST API"

    flow:

      - get:
          url: "/hello"

      - get:
          url: "/data"

      - get:
          url: "/users"

      - get:
          url: "/users/1"

      - post:
          url: "/users"
          json:
            name: "Alice"
            email: "alice@example.com"
EOF

fi

# --------------------------------------------------
# Runtime targets
# --------------------------------------------------

declare -A TARGETS

TARGETS[swoole]="http://127.0.0.1:9501"
TARGETS[openswoole]="http://127.0.0.1:9502"
TARGETS[roadrunner]="http://127.0.0.1:8080"
TARGETS[adonisjs]="http://127.0.0.1:3333"
TARGETS[nodejs]="http://127.0.0.1:3000"
TARGETS[laravel-octane]="http://127.0.0.1:8000"

# --------------------------------------------------
# Select runtimes
# --------------------------------------------------

RUNTIMES=(
    swoole
    openswoole
    roadrunner
    adonisjs
    nodejs
    laravel-octane
)

# --------------------------------------------------
# Check servers
# --------------------------------------------------

echo
echo "======================================"
echo " Checking runtimes"
echo "======================================"

AVAILABLE=()

for runtime in "${RUNTIMES[@]}"; do

    url="${TARGETS[$runtime]}"

    if check_url "$runtime" "$url"; then
        AVAILABLE+=("$runtime")
    else
        echo "  Skipping $runtime"
    fi

done

if [ "${#AVAILABLE[@]}" -eq 0 ]; then
    echo
    echo "ERROR: No runtime is running."
    exit 1
fi

# --------------------------------------------------
# Run tests
# --------------------------------------------------

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"

RUN_DIR="$RESULTS_DIR/$TIMESTAMP"

mkdir -p "$RUN_DIR"

echo
echo "======================================"
echo " Running benchmarks"
echo "======================================"

for runtime in "${AVAILABLE[@]}"; do

    url="${TARGETS[$runtime]}"

    output="$RUN_DIR/${runtime}.json"

    run_artillery \
        "$runtime" \
        "$url" \
        "$output"

done

# --------------------------------------------------
# Summary
# --------------------------------------------------

echo
echo "======================================"
echo " Benchmark completed"
echo "======================================"
echo
echo "Results:"
echo
echo "  $RUN_DIR"
echo

for file in "$RUN_DIR"/*.json; do

    [ -f "$file" ] || continue

    runtime="$(basename "$file" .json)"

    echo "--------------------------------------"
    echo "$runtime"
    echo "--------------------------------------"

    if command_exists jq; then

        jq '{
          requestsCompleted,
          requestsFailed,
          latency: {
            min: latency.min,
            median: latency.median,
            p95: latency.p95,
            p99: latency.p99,
            max: latency.max
          },
          rps: {
            min: rps.min,
            max: rps.max,
            mean: rps.mean
          }
        }' "$file"

    else
        echo "Install jq for a readable summary:"
        echo "  sudo apt install jq"
    fi

    echo

done
