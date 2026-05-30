#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAP_NAME="${1:-garage}"
LAUNCH_MAP_NAME="${MAP_NAME}"

case "${MAP_NAME}" in
  cave|garage|factory)
    ;;
  *)
    echo "[run_until_finish] Unsupported map '${MAP_NAME}'. Available maps in this repo: cave, garage, factory." >&2
    exit 2
    ;;
esac
USE_GPU="${USE_GPU:-true}"
TRIGGER_X="${TRIGGER_X:-3.0}"
TRIGGER_Y="${TRIGGER_Y:-0.0}"
TRIGGER_Z="${TRIGGER_Z:-1.0}"
TRIGGER_RETRY_SEC="${TRIGGER_RETRY_SEC:-0.2}"
TRIGGER_TIMEOUT_SEC="${TRIGGER_TIMEOUT_SEC:-6}"
FINISH_TIMEOUT_SEC="${FINISH_TIMEOUT_SEC:-1500}"
IGNORE_SIGINT_UNTIL_FINISH="${IGNORE_SIGINT_UNTIL_FINISH:-true}"

FINISH_REACHED="false"
INTERRUPT_NOTICE_SHOWN="false"

RESULT_DIR="${WORKSPACE_DIR}/results"
mkdir -p "${RESULT_DIR}"
RESULTS_CSV_DIR="${WORKSPACE_DIR}/results_csv"
RUN_TABLE_FILE="${RESULTS_CSV_DIR}/run_metrics_table.tsv"
COMPARE_TABLE_FILE="${RESULTS_CSV_DIR}/paper_vs_run_table.tsv"
PAPER_REF_FILE="${RESULTS_CSV_DIR}/paper_table_i_reference.tsv"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${RESULT_DIR}/${MAP_NAME}_${RUN_ID}.log"
METRICS_FILE="${RESULT_DIR}/${MAP_NAME}_${RUN_ID}_metrics.txt"
RUNTIME_STATS_FILE="${RESULT_DIR}/${MAP_NAME}_${RUN_ID}_runtime_stats.txt"

init_results_tables() {
  mkdir -p "${RESULTS_CSV_DIR}"

  if [[ ! -f "${RUN_TABLE_FILE}" ]]; then
    {
      echo -e "run_id\tmap\tlaunch_file\tscenario_yaml\tmetrics_file\truntime_stats_file\tlog_file\tuse_gpu\ttrigger_xyz\tfinish_timeout_sec\ttrigger_timeout_sec\ttrigger_retry_sec\ttrigger_attempts\ttrigger_ack_sec\ttrigger_callback_seen\texp_time_sec\tavg_vel_mps\tavg_tm_s\tmax_tm_s\texp_finished\tpath_length_m\tavg_tm_ms\tmax_tm_ms"
    } >"${RUN_TABLE_FILE}"
  fi

  if [[ ! -f "${COMPARE_TABLE_FILE}" ]]; then
    {
      echo -e "run_id\tmap\tpaper_scene\tpaper_exp_time_sec\tpaper_avg_vel_mps\tpaper_avg_tm_s\tpaper_max_tm_s\tpaper_exp_finished\trun_exp_time_sec\trun_avg_vel_mps\trun_avg_tm_s\trun_max_tm_s\trun_exp_finished\tdelta_exp_time_sec\tdelta_avg_vel_mps\tdelta_avg_tm_s\tdelta_max_tm_s\tdelta_exp_time_pct\tdelta_avg_vel_pct\tdelta_avg_tm_pct\tdelta_max_tm_pct"
    } >"${COMPARE_TABLE_FILE}"
  fi

  if [[ ! -f "${PAPER_REF_FILE}" ]]; then
    {
      echo -e "paper_scene\tmethod\texp_time_sec↓\tavg_vel_mps↑\tavg_tm_s↓\tmax_tm_s↓\texp_fin↑\tsource"
      echo -e "cave\tERRT [20]\t-\t2.19\t0.65\t0.77\tNo\tarXiv:2410.14203v2 Table I"
      echo -e "cave\tM3 [4]\t-\t1.96\t0.02\t0.07\tNo\tarXiv:2410.14203v2 Table I"
      echo -e "cave\tFUEL [1]\t-\t1.43\t0.48\t3.98\tNo\tarXiv:2410.14203v2 Table I"
      echo -e "cave\tProposed\t1288.2\t2.68\t0.09\t0.18\tYes\tarXiv:2410.14203v2 Table I"
      echo -e "garage\tERRT [20]\t-\t1.92\t0.61\t0.82\tNo\tarXiv:2410.14203v2 Table I"
      echo -e "garage\tM3 [4]\t-\t1.91\t0.02\t0.06\tNo\tarXiv:2410.14203v2 Table I"
      echo -e "garage\tFUEL [1]\t1486.5\t1.55\t0.48\t3.56\tYes\tarXiv:2410.14203v2 Table I"
      echo -e "garage\tProposed\t716.9\t3.10\t0.05\t0.10\tYes\tarXiv:2410.14203v2 Table I"
      echo -e "campus\tERRT [20]\t-\t1.92\t0.82\t1.17\tNo\tarXiv:2410.14203v2 Table I"
      echo -e "campus\tM3 [4]\t-\t1.93\t0.08\t2.60\tNo\tarXiv:2410.14203v2 Table I"
      echo -e "campus\tFUEL [1]\t-\t1.14\t2.40\t16.72\tNo\tarXiv:2410.14203v2 Table I"
      echo -e "campus\tProposed\t908.2\t2.58\t0.08\t0.24\tYes\tarXiv:2410.14203v2 Table I"
    } >"${PAPER_REF_FILE}"
  fi
}

append_finish_tables() {
  local launch_file scenario_yaml
  local run_exp_fin_label
  local paper_scene paper_exp_time paper_avg_vel paper_avg_tm paper_max_tm paper_exp_finished
  local delta_exp_time delta_avg_vel delta_avg_tm delta_max_tm
  local pct_exp_time pct_avg_vel pct_avg_tm pct_max_tm

  launch_file="${LAUNCH_MAP_NAME}.launch"
  scenario_yaml="src/global_planner/exploration_manager/config/${LAUNCH_MAP_NAME}.yaml"

  paper_scene=""
  paper_exp_time="NA"
  paper_avg_vel="NA"
  paper_avg_tm="NA"
  paper_max_tm="NA"
  paper_exp_finished="NA"

  case "${MAP_NAME}" in
    garage)
      paper_scene="garage"
      paper_exp_time="716.9"
      paper_avg_vel="3.10"
      paper_avg_tm="0.05"
      paper_max_tm="0.10"
      paper_exp_finished="true"
      ;;
    cave)
      paper_scene="cave"
      paper_exp_time="1288.2"
      paper_avg_vel="2.68"
      paper_avg_tm="0.09"
      paper_max_tm="0.18"
      paper_exp_finished="true"
      ;;
    factory)
      # Table I does not provide a factory scene; keep this run recorded without paper comparison.
      paper_scene="NA"
      ;;
    *)
      paper_scene="NA"
      ;;
  esac

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${RUN_ID}" "${MAP_NAME}" "${launch_file}" "${scenario_yaml}" "${METRICS_FILE}" "${RUNTIME_STATS_FILE}" "${LOG_FILE}" \
    "${USE_GPU}" "${TRIGGER_X},${TRIGGER_Y},${TRIGGER_Z}" "${FINISH_TIMEOUT_SEC}" "${TRIGGER_TIMEOUT_SEC}" "${TRIGGER_RETRY_SEC}" \
    "${TRIGGER_ATTEMPTS}" "${TRIGGER_ACK_SEC}" "${TRIGGER_CALLBACK_SEEN}" "${ELAPSED_SEC}" "${AVG_VEL_MPS}" "${AVG_TM_S}" "${MAX_TM_S}" \
    "${FINISH_DETECTED}" "${PATH_LENGTH_M}" "${AVG_TM_MS}" "${MAX_TM_MS}" >>"${RUN_TABLE_FILE}"

  if [[ "${paper_exp_time}" == "NA" ]]; then
    delta_exp_time="NA"
    delta_avg_vel="NA"
    delta_avg_tm="NA"
    delta_max_tm="NA"
    pct_exp_time="NA"
    pct_avg_vel="NA"
    pct_avg_tm="NA"
    pct_max_tm="NA"
  else
    read -r delta_exp_time delta_avg_vel delta_avg_tm delta_max_tm pct_exp_time pct_avg_vel pct_avg_tm pct_max_tm <<EOF
$(python3 - <<PY
paper_exp_time = float("${paper_exp_time}")
paper_avg_vel = float("${paper_avg_vel}")
paper_avg_tm = float("${paper_avg_tm}")
paper_max_tm = float("${paper_max_tm}")
run_exp_time = float("${ELAPSED_SEC}")
run_avg_vel = float("${AVG_VEL_MPS}")
run_avg_tm = float("${AVG_TM_S}")
run_max_tm = float("${MAX_TM_S}")

def safe_pct(delta, base):
    return (delta / base * 100.0) if abs(base) > 1e-9 else 0.0

d_exp = run_exp_time - paper_exp_time
d_vel = run_avg_vel - paper_avg_vel
d_avg_tm = run_avg_tm - paper_avg_tm
d_max_tm = run_max_tm - paper_max_tm

print(
    f"{d_exp:.3f} {d_vel:.3f} {d_avg_tm:.6f} {d_max_tm:.6f} "
    f"{safe_pct(d_exp, paper_exp_time):.2f} {safe_pct(d_vel, paper_avg_vel):.2f} "
    f"{safe_pct(d_avg_tm, paper_avg_tm):.2f} {safe_pct(d_max_tm, paper_max_tm):.2f}"
)
PY
)
EOF
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${RUN_ID}" "${MAP_NAME}" "${paper_scene}" "${paper_exp_time}" "${paper_avg_vel}" "${paper_avg_tm}" "${paper_max_tm}" "${paper_exp_finished}" \
    "${ELAPSED_SEC}" "${AVG_VEL_MPS}" "${AVG_TM_S}" "${MAX_TM_S}" "${FINISH_DETECTED}" \
    "${delta_exp_time}" "${delta_avg_vel}" "${delta_avg_tm}" "${delta_max_tm}" \
    "${pct_exp_time}" "${pct_avg_vel}" "${pct_avg_tm}" "${pct_max_tm}" >>"${COMPARE_TABLE_FILE}"

  run_exp_fin_label="No"
  if [[ "${FINISH_DETECTED}" == "true" ]]; then
    run_exp_fin_label="Yes"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${MAP_NAME}" "Measured" "${ELAPSED_SEC}" "${AVG_VEL_MPS}" "${AVG_TM_S}" "${MAX_TM_S}" "${run_exp_fin_label}" "Measured run_id=${RUN_ID} (FINISH)" >>"${PAPER_REF_FILE}"
}

export ROS_MASTER_URI="http://localhost:11311"
export ROS_IP="127.0.0.1"

source /home/robot/anaconda3/etc/profile.d/conda.sh
conda activate epic_repro
source /opt/ros/noetic/setup.bash
source "${WORKSPACE_DIR}/devel/setup.bash"

ensure_gpu_ready() {
  if [[ "${USE_GPU}" != "true" ]]; then
    echo "[run_until_finish] USE_GPU must be true for paper-aligned runs. Current USE_GPU=${USE_GPU}" >&2
    exit 2
  fi

  if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "[run_until_finish] nvidia-smi was not found. GPU is required for this run policy." >&2
    exit 2
  fi

  if ! nvidia-smi -L >/dev/null 2>&1; then
    echo "[run_until_finish] No visible NVIDIA GPU detected. Aborting by policy." >&2
    exit 2
  fi
}

trigger_with_retry() {
  local start_ms now_ms deadline_ms attempts
  start_ms="$(date +%s%3N)"
  deadline_ms=$((start_ms + TRIGGER_TIMEOUT_SEC * 1000))
  attempts=0

  while true; do
    attempts=$((attempts + 1))

    # README-compatible trigger path
    rostopic pub -1 /move_base_simple/goal geometry_msgs/PoseStamped "{header: {frame_id: 'world'}, pose: {position: {x: ${TRIGGER_X}, y: ${TRIGGER_Y}, z: ${TRIGGER_Z}}, orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}}}" >/dev/null 2>&1 || true

    # Direct fallback to FSM input topic
    rostopic pub -1 /waypoint_generator/waypoints nav_msgs/Path "{header: {frame_id: 'world'}, poses: [{header: {frame_id: 'world'}, pose: {position: {x: ${TRIGGER_X}, y: ${TRIGGER_Y}, z: ${TRIGGER_Z}}, orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}}}]}" >/dev/null 2>&1 || true

    now_ms="$(date +%s%3N)"
    if (( now_ms >= deadline_ms )); then
      TRIGGER_ACK_SEC="$(python3 - <<PY
elapsed_ms = ${now_ms} - ${start_ms}
print(f"{elapsed_ms/1000.0:.3f}")
PY
)"
      TRIGGER_ATTEMPTS="${attempts}"
      echo "[run_until_finish] Trigger burst sent for ${TRIGGER_ACK_SEC}s with ${TRIGGER_ATTEMPTS} attempts"
      return 0
    fi

    sleep "${TRIGGER_RETRY_SEC}"
  done
}

cleanup() {
  if [[ -n "${LAUNCH_PID:-}" ]] && kill -0 "${LAUNCH_PID}" 2>/dev/null; then
    # roslaunch is started in a dedicated session, so terminate its process group.
    kill -INT "-${LAUNCH_PID}" 2>/dev/null || kill -INT "${LAUNCH_PID}" 2>/dev/null || true
    wait "${LAUNCH_PID}" || true
  fi
}

on_sigint() {
  if [[ "${IGNORE_SIGINT_UNTIL_FINISH}" == "true" && "${FINISH_REACHED}" != "true" ]]; then
    if [[ "${INTERRUPT_NOTICE_SHOWN}" != "true" ]]; then
      echo "[run_until_finish] Ctrl+C was ignored (waiting for FINISH)."
      echo "[run_until_finish] To force stop, send SIGTERM or set IGNORE_SIGINT_UNTIL_FINISH=false."
      INTERRUPT_NOTICE_SHOWN="true"
    fi
    return 0
  fi

  echo "[run_until_finish] Interrupted by Ctrl+C. Cleaning up..."
  exit 130
}

trap cleanup EXIT TERM
trap on_sigint INT

# Start roslaunch in its own session so terminal Ctrl+C does not kill it accidentally.
setsid roslaunch --skip-log-check epic_planner "${LAUNCH_MAP_NAME}.launch" use_gpu:="${USE_GPU}" > >(tee "${LOG_FILE}") 2>&1 &
LAUNCH_PID=$!

echo "[run_until_finish] roslaunch pid=${LAUNCH_PID}"

# Wait until ROS master and topics are ready.
ready=false
for _ in $(seq 1 120); do
  if rostopic list >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 0.5
done

if [[ "${ready}" != "true" ]]; then
  echo "[run_until_finish] ROS master did not become ready in time." >&2
  exit 1
fi

# Baseline-compatible startup trigger with retry to avoid subscriber timing loss.
ensure_gpu_ready

TRIGGER_ACK_SEC=""
TRIGGER_ATTEMPTS="0"
if ! trigger_with_retry; then
  exit 1
fi

# Wait for FINISH marker on /planning/state and collect runtime metrics.
set +e
(
trap '' INT
RUNTIME_STATS_FILE="${RUNTIME_STATS_FILE}" timeout "${FINISH_TIMEOUT_SEC}" python3 - <<'PY'
import math
import os
import time

import rospy
from std_msgs.msg import Float32
from visualization_msgs.msg import Marker


stats_path = os.environ["RUNTIME_STATS_FILE"]

start_wall = time.time()
finish_detected = False
finish_wall = None

last_pos = None
path_length_m = 0.0

time_cost_count = 0
time_cost_sum_ms = 0.0
time_cost_max_ms = 0.0


def write_stats_file():
    elapsed = (finish_wall if finish_wall is not None else time.time()) - start_wall
    avg_tm_ms = (time_cost_sum_ms / time_cost_count) if time_cost_count > 0 else 0.0
    with open(stats_path, "w", encoding="utf-8") as f:
        f.write(f"finish_detected={'true' if finish_detected else 'false'}\n")
        f.write(f"elapsed_sec={elapsed:.3f}\n")
        f.write(f"path_length_m={path_length_m:.3f}\n")
        f.write(f"avg_tm_ms={avg_tm_ms:.6f}\n")
        f.write(f"max_tm_ms={time_cost_max_ms:.6f}\n")


def cb(msg: Marker):
    global finish_detected, finish_wall, last_pos, path_length_m
    pos = (msg.pose.position.x, msg.pose.position.y, msg.pose.position.z)
    if last_pos is not None:
        dx = pos[0] - last_pos[0]
        dy = pos[1] - last_pos[1]
        dz = pos[2] - last_pos[2]
        path_length_m += math.sqrt(dx * dx + dy * dy + dz * dz)
    last_pos = pos

    if msg.text.strip() == "FINISH" and not finish_detected:
        finish_detected = True
        finish_wall = time.time()
        rospy.signal_shutdown("finish reached")


def time_cost_cb(msg: Float32):
    global time_cost_count, time_cost_sum_ms, time_cost_max_ms
    v = float(msg.data)
    time_cost_count += 1
    time_cost_sum_ms += v
    if v > time_cost_max_ms:
        time_cost_max_ms = v


rospy.init_node("finish_waiter", anonymous=True)
rospy.Subscriber("/planning/state", Marker, cb, queue_size=10)
rospy.Subscriber("/time_cost", Float32, time_cost_cb, queue_size=100)

try:
    rospy.spin()
finally:
    write_stats_file()
PY
)
WAIT_CODE=$?
set -e

FINISH_DETECTED="false"
ELAPSED_SEC=""
PATH_LENGTH_M=""
AVG_TM_MS=""
MAX_TM_MS=""
if [[ -f "${RUNTIME_STATS_FILE}" ]]; then
  while IFS='=' read -r key value; do
    case "${key}" in
      finish_detected) FINISH_DETECTED="${value}" ;;
      elapsed_sec) ELAPSED_SEC="${value}" ;;
      path_length_m) PATH_LENGTH_M="${value}" ;;
      avg_tm_ms) AVG_TM_MS="${value}" ;;
      max_tm_ms) MAX_TM_MS="${value}" ;;
    esac
  done <"${RUNTIME_STATS_FILE}"
fi

if [[ -z "${ELAPSED_SEC}" ]]; then
  ELAPSED_SEC="0.000"
fi
if [[ -z "${PATH_LENGTH_M}" ]]; then
  PATH_LENGTH_M="0.000"
fi
if [[ -z "${AVG_TM_MS}" ]]; then
  AVG_TM_MS="0.000000"
fi
if [[ -z "${MAX_TM_MS}" ]]; then
  MAX_TM_MS="0.000000"
fi

AVG_VEL_MPS="$(python3 - <<PY
elapsed = float("${ELAPSED_SEC}")
dist = float("${PATH_LENGTH_M}")
print(f"{(dist / elapsed) if elapsed > 1e-9 else 0.0:.3f}")
PY
)"
AVG_TM_S="$(python3 - <<PY
print(f"{float('${AVG_TM_MS}')/1000.0:.6f}")
PY
)"
MAX_TM_S="$(python3 - <<PY
print(f"{float('${MAX_TM_MS}')/1000.0:.6f}")
PY
)"

if [[ "${FINISH_DETECTED}" == "true" ]]; then
  FINISH_REACHED="true"
  TRIGGER_CALLBACK_SEEN="false"
  if grep -q "Triggered!" "${LOG_FILE}"; then
    TRIGGER_CALLBACK_SEEN="true"
  fi

  # DEBUG_ONLY: keep this block around while tuning trigger timing.
  # LABEL_MAP_KB="$(grep -oE 'label_map_size: .* = [0-9.]+KB' "${LOG_FILE}" | tail -n 1 | sed -E 's/.*= ([0-9.]+)KB/\1/' || true)"
  # FRT_MAP2="$(grep -oE 'frt_map_size2 = [0-9.]+' "${LOG_FILE}" | tail -n 1 | awk '{print $3}' || true)"
  # FRT_MAP3="$(grep -oE 'frt_map_size3 = [0-9.]+' "${LOG_FILE}" | tail -n 1 | awk '{print $3}' || true)"

  {
    echo "run_id=${RUN_ID}"
    echo "map=${MAP_NAME}"
    echo "use_gpu=${USE_GPU}"
    echo "trigger_xyz=${TRIGGER_X},${TRIGGER_Y},${TRIGGER_Z}"
    echo "finish_timeout_sec=${FINISH_TIMEOUT_SEC}"
    echo "trigger_timeout_sec=${TRIGGER_TIMEOUT_SEC}"
    echo "trigger_retry_sec=${TRIGGER_RETRY_SEC}"
    echo "trigger_attempts=${TRIGGER_ATTEMPTS}"
    echo "trigger_ack_sec=${TRIGGER_ACK_SEC}"
    echo "trigger_callback_seen=${TRIGGER_CALLBACK_SEEN}"

    # Paper-aligned metrics (Table I style)
    echo "exp_time_sec=${ELAPSED_SEC}"
    echo "avg_vel_mps=${AVG_VEL_MPS}"
    echo "avg_tm_s=${AVG_TM_S}"
    echo "max_tm_s=${MAX_TM_S}"
    echo "exp_finished=${FINISH_DETECTED}"

    # DEBUG_ONLY: uncomment if you need to compare aborted runs.
    # echo "elapsed_sec=${ELAPSED_SEC}"
    # echo "path_length_m=${PATH_LENGTH_M}"
    # echo "finish_detected=${FINISH_DETECTED}"
    # echo "finish_wait_exit_code=${WAIT_CODE}"
    # echo "label_map_kb=${LABEL_MAP_KB}"
    # echo "label_map_mb=${LABEL_MAP_MB}"
    # echo "frt_map_size2=${FRT_MAP2}"
    # echo "frt_map_size3=${FRT_MAP3}"

    # Artifacts
    echo "log_file=${LOG_FILE}"
    # echo "runtime_stats_file=${RUNTIME_STATS_FILE}"
  } >"${METRICS_FILE}"

  init_results_tables
  append_finish_tables

  echo "[run_until_finish] FINISH detected."
  echo "[run_until_finish] run_table=${RUN_TABLE_FILE}"
  echo "[run_until_finish] compare_table=${COMPARE_TABLE_FILE}"
else
  rm -f "${METRICS_FILE}"
  echo "[run_until_finish] FINISH wait exited with code ${WAIT_CODE}. Metrics were skipped." >&2
fi

echo "[run_until_finish] elapsed_sec=${ELAPSED_SEC}"
echo "[run_until_finish] avg_vel_mps=${AVG_VEL_MPS}"
echo "[run_until_finish] avg_tm_s=${AVG_TM_S}, max_tm_s=${MAX_TM_S}"
echo "[run_until_finish] metrics_file=${METRICS_FILE}"
