#!/usr/bin/env bash
set -euo pipefail
HOST=${1:-localhost}
PORT=${2:-8001}
PATHNAME=${3:-/}
N=${N:-10}

echo "Spawning $N client requests to http://$HOST:$PORT$PATHNAME"
pids=()
for i in $(seq 1 "$N"); do
  python3 src/client.py "$HOST" "$PORT" "${PATHNAME#/}" > /dev/null &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done
echo "Done."