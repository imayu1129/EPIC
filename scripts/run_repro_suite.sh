#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${WORKSPACE_DIR}"

RUNS="${RUNS:-5}"
FINISH_TIMEOUT_SEC="${FINISH_TIMEOUT_SEC:-1500}"
SUMMARY_FILE="${SUMMARY_FILE:-results_csv/repro_summary_latest.tsv}"

MAP_LIST=("$@")
if [[ ${#MAP_LIST[@]} -eq 0 ]]; then
  MAP_LIST=(cave garage)
fi

for map in "${MAP_LIST[@]}"; do
  case "${map}" in
    cave|garage)
      ;;
    *)
      echo "[run_repro_suite] Unsupported map '${map}'. Supported maps: cave, garage" >&2
      exit 2
      ;;
  esac
done

echo "[run_repro_suite] maps=${MAP_LIST[*]}"
echo "[run_repro_suite] runs_per_map=${RUNS}, finish_timeout_sec=${FINISH_TIMEOUT_SEC}"

for map in "${MAP_LIST[@]}"; do
  for i in $(seq 1 "${RUNS}"); do
    echo "[run_repro_suite] start map=${map} run=${i}/${RUNS}"
    USE_GPU=true FINISH_TIMEOUT_SEC="${FINISH_TIMEOUT_SEC}" ./scripts/run_until_finish.sh "${map}"
    echo "[run_repro_suite] done map=${map} run=${i}/${RUNS}"
  done
done

export RUNS SUMMARY_FILE
MAP_LIST_ENV="${MAP_LIST[*]}"
export MAP_LIST_ENV

python3 - <<'PY'
import csv
import os
from statistics import mean

run_table = os.path.join('results_csv', 'run_metrics_table.tsv')
summary_file = os.environ.get('SUMMARY_FILE', 'results_csv/repro_summary_latest.tsv')
runs = int(os.environ.get('RUNS', '5'))
map_list = os.environ.get('MAP_LIST_ENV', 'cave garage').split()

rows = []
with open(run_table, newline='', encoding='utf-8') as f:
    reader = csv.DictReader(f, delimiter='\t')
    for row in reader:
        if row.get('use_gpu') != 'true':
            continue
        if row.get('exp_finished') != 'true':
            continue
        rows.append(row)

for r in rows:
    r['_run_id'] = r.get('run_id', '')

with open(summary_file, 'w', encoding='utf-8', newline='') as f:
    writer = csv.writer(f, delimiter='\t')
    writer.writerow([
        'map', 'n', 'mean_exp_time_sec', 'mean_avg_vel_mps',
        'mean_avg_tm_s', 'mean_max_tm_s', 'run_ids'
    ])

    for scene in map_list:
        subset = [r for r in rows if r.get('map') == scene]
        subset.sort(key=lambda x: x['_run_id'])
        subset = subset[-runs:]

        if len(subset) < runs:
            writer.writerow([scene, len(subset), 'NA', 'NA', 'NA', 'NA', ''])
            continue

        writer.writerow([
            scene,
            len(subset),
            f"{mean(float(x['exp_time_sec']) for x in subset):.3f}",
            f"{mean(float(x['avg_vel_mps']) for x in subset):.3f}",
            f"{mean(float(x['avg_tm_s']) for x in subset):.6f}",
            f"{mean(float(x['max_tm_s']) for x in subset):.6f}",
            ','.join(x['_run_id'] for x in subset),
        ])

print(f"[run_repro_suite] summary_written={summary_file}")
PY

echo "[run_repro_suite] completed"
