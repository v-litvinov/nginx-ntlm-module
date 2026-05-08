#!/usr/bin/env bash
#
# Run the test suite. Starts the mock backend, runs prove, kills the backend.
#
# Requires:
#   - nginx built with this module on PATH (or TEST_NGINX_BINARY set)
#   - perl with Test::Nginx::Socket installed (cpan Test::Nginx)
#   - node >= 14
#
# Usage:
#   t/run.sh                # run all
#   t/run.sh t/03-pinning.t # run a single file
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

PORT="${TEST_BACKEND_PORT:-8080}"
export TEST_NGINX_BACKEND_PORT="$PORT"

# Start mock backend
PORT="$PORT" node "$HERE/backend/server.js" &
BACKEND_PID=$!
trap 'kill "$BACKEND_PID" 2>/dev/null || true' EXIT

# Wait until backend accepts connections (up to ~3s)
for _ in $(seq 1 30); do
    if (echo > "/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then break; fi
    sleep 0.1
done

cd "$ROOT"

if [[ $# -gt 0 ]]; then
    prove -v "$@"
else
    prove -r t
fi
