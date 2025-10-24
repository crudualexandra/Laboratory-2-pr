#!/usr/bin/env bash
set -euo pipefail

host=${1:?host}; port=${2:?port}; path=${3:?path}
N=${N:-10}
url="http://${host}:${port}${path}"

echo "Spawning $N client requests to $url"
pids=()
for i in $(seq 1 "$N"); do
  curl -s -o /dev/null "$url" &   
  pids+=($!)
done
for pid in "${pids[@]}"; do
  wait "$pid"                   
done
echo "Done."
