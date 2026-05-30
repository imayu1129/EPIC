#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${WORKSPACE_DIR}"

FINISH_TIMEOUT_SEC="${FINISH_TIMEOUT_SEC:-1500}"
TRIGGER_TIMEOUT_SEC="${TRIGGER_TIMEOUT_SEC:-10}"
MAP_LIST=("$@")

if [[ ${#MAP_LIST[@]} -eq 0 ]]; then
  MAP_LIST=(cave factory)
fi

echo "[run_map_suite] maps=${MAP_LIST[*]}"
echo "[run_map_suite] finish_timeout_sec=${FINISH_TIMEOUT_SEC}, trigger_timeout_sec=${TRIGGER_TIMEOUT_SEC}"

for map in "${MAP_LIST[@]}"; do
  echo "[run_map_suite] start map=${map}"
  FINISH_TIMEOUT_SEC="${FINISH_TIMEOUT_SEC}" TRIGGER_TIMEOUT_SEC="${TRIGGER_TIMEOUT_SEC}" \
    ./scripts/run_until_finish.sh "${map}"
  echo "[run_map_suite] done map=${map}"
done
