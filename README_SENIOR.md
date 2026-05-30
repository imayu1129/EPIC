# EPIC Reproduction Guide (For Lab Senior)

This guide is focused on reproducible execution on Ubuntu 20.04 + ROS Noetic with GPU acceleration.

## 1) What Is Included in This Fork

- Reproducible run wrapper: `scripts/run_until_finish.sh`
- Multi-map runner: `scripts/run_map_suite.sh`
- Auto-generated result tables in `results_csv/`
- Table-I-aligned reference table with metric directions in `results_csv/paper_table_i_reference.tsv`

## 2) Environment Requirements

- Ubuntu 20.04
- ROS Noetic
- NVIDIA GPU with driver + `nvidia-smi`
- `catkin build`
- Conda environment named `epic_repro` (current script assumes this name)

## 3) Build

```bash
git clone https://github.com/imayu1129/EPIC.git
cd EPIC
catkin build
```

## 4) Map Data

Place simulation `.pcd` files in:

- `src/MARSIM/map_generator/resource/`

Expected maps for this repository:

- `cave.pcd`
- `garage.pcd`
- `factory.pcd`

Note on campus:

- The paper reports a `campus` scene, but this public codebase currently exposes `cave/garage/factory` in launch/config.
- `scripts/run_until_finish.sh` intentionally rejects unsupported map names to avoid mislabeling.

## 5) Single Run (GPU, FINISH-only metrics)

```bash
USE_GPU=true FINISH_TIMEOUT_SEC=1500 ./scripts/run_until_finish.sh cave
```

or

```bash
USE_GPU=true FINISH_TIMEOUT_SEC=1500 ./scripts/run_until_finish.sh garage
```

The run wrapper:

- validates GPU availability
- publishes startup trigger automatically
- waits for planner state `FINISH`
- writes metrics only when FINISH is detected

## 6) Recommended Repetition (5 runs each)

```bash
for i in $(seq 1 5); do
  echo "[cave] run ${i}/5"
  USE_GPU=true FINISH_TIMEOUT_SEC=1500 ./scripts/run_until_finish.sh cave
done

for i in $(seq 1 5); do
  echo "[garage] run ${i}/5"
  USE_GPU=true FINISH_TIMEOUT_SEC=1500 ./scripts/run_until_finish.sh garage
done
```

## 7) Output Files

Per run:

- `results/<map>_<run_id>.log`
- `results/<map>_<run_id>_metrics.txt`
- `results/<map>_<run_id>_runtime_stats.txt`

Aggregated tables:

- `results_csv/run_metrics_table.tsv`
- `results_csv/paper_vs_run_table.tsv`
- `results_csv/paper_table_i_reference.tsv`

## 8) Compute Mean Over Last 5 GPU FINISH Runs Per Map

```bash
python3 - <<'PY'
import csv
from statistics import mean

path = 'results_csv/run_metrics_table.tsv'
rows = []
with open(path, newline='') as f:
    r = csv.DictReader(f, delimiter='\t')
    for row in r:
        if row.get('use_gpu') != 'true':
            continue
        if row.get('exp_finished') != 'true':
            continue
        rows.append(row)

for scene in ('cave', 'garage'):
    s = [x for x in rows if x.get('map') == scene]
    s = s[-5:]
    if len(s) < 5:
        print(f'{scene}: only {len(s)} GPU FINISH runs found (need 5)')
        continue
    exp_time = mean(float(x['exp_time_sec']) for x in s)
    avg_vel = mean(float(x['avg_vel_mps']) for x in s)
    avg_tm = mean(float(x['avg_tm_s']) for x in s)
    max_tm = mean(float(x['max_tm_s']) for x in s)
    print(f'{scene}: n=5, exp_time={exp_time:.3f}, avg_vel={avg_vel:.3f}, avg_tm={avg_tm:.6f}, max_tm={max_tm:.6f}')
PY
```

## 9) Metric Meaning

- `exp_time_sec`: total exploration time (smaller is better)
- `avg_vel_mps`: average velocity during exploration (larger is better)
- `avg_tm_s`: mean planner computation time per cycle (smaller is better)
- `max_tm_s`: maximum planner computation time per cycle (smaller is better)
- `exp_fin`: completion status (`Yes`/`No`, `Yes` is better)

## 10) Troubleshooting

- If GPU check fails, verify `nvidia-smi` output first.
- If you see repeated `no odom`, check simulator/driver compatibility and launch order.
- If a run times out before `FINISH`, no metrics are appended by design.
