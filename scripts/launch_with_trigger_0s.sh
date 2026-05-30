#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAP_NAME="${1:-garage}"
USE_GPU="${USE_GPU:-false}"
TRIGGER_X="${TRIGGER_X:-3.0}"
TRIGGER_Y="${TRIGGER_Y:-0.0}"
TRIGGER_Z="${TRIGGER_Z:-1.0}"
TRIGGER_RETRY_SEC="${TRIGGER_RETRY_SEC:-0.2}"
TRIGGER_TIMEOUT_SEC="${TRIGGER_TIMEOUT_SEC:-6}"
RVIZ_ALWAYS_ON_TOP="${RVIZ_ALWAYS_ON_TOP:-true}"
RVIZ_WINDOW_HINT="${RVIZ_WINDOW_HINT:-traj.rviz}"
ON_TOP_TIMEOUT_SEC="${ON_TOP_TIMEOUT_SEC:-20}"

source /home/robot/anaconda3/etc/profile.d/conda.sh
conda activate epic_repro
source /opt/ros/noetic/setup.bash
source "${WORKSPACE_DIR}/devel/setup.bash"

# Force local ROS networking to avoid remote URI/IP drift.
unset ROS_HOSTNAME
export ROS_MASTER_URI="http://localhost:11311"
export ROS_IP="127.0.0.1"

trigger_with_retry() {
  local start_ms now_ms deadline_ms
  start_ms="$(date +%s%3N)"
  deadline_ms=$((start_ms + TRIGGER_TIMEOUT_SEC * 1000))

  while true; do
    # Keep publishing from startup until planner trajectory appears.
    # 1) README-compatible trigger path via 2D Nav Goal topic.
    rostopic pub -1 /move_base_simple/goal geometry_msgs/PoseStamped "{header: {frame_id: 'world'}, pose: {position: {x: ${TRIGGER_X}, y: ${TRIGGER_Y}, z: ${TRIGGER_Z}}, orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}}}" >/dev/null 2>&1 || true

    # 2) Direct FSM-input fallback to avoid subscriber timing loss.
    rostopic pub -1 /waypoint_generator/waypoints nav_msgs/Path "{header: {frame_id: 'world'}, poses: [{header: {frame_id: 'world'}, pose: {position: {x: ${TRIGGER_X}, y: ${TRIGGER_Y}, z: ${TRIGGER_Z}}, orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}}}]}" >/dev/null 2>&1 || true

    # Stop publishing once FSM leaves WAIT_TRIGGER.
    local state_msg
    state_msg="$(timeout 0.8 rostopic echo -n 1 /planning/state 2>/dev/null || true)"
    if grep -Eq "text: '(PLAN_TRAJ|EXEC_TRAJ|CAUTION|FINISH)'" <<<"${state_msg}"; then
      now_ms="$(date +%s%3N)"
      echo "[launch_with_trigger_0s] Trigger confirmed after $((now_ms - start_ms)) ms"
      return 0
    fi

    now_ms="$(date +%s%3N)"
    if (( now_ms >= deadline_ms )); then
      echo "[launch_with_trigger_0s] Trigger burst finished after $((now_ms - start_ms)) ms"
      return 0
    fi

    sleep "${TRIGGER_RETRY_SEC}"
  done
}

set_rviz_on_top() {
  if [[ "${RVIZ_ALWAYS_ON_TOP}" != "true" ]]; then
    return 0
  fi

  if ! command -v wmctrl >/dev/null 2>&1; then
    echo "[launch_with_trigger_0s] WARN: wmctrl not found. RViz always-on-top is skipped."
    return 0
  fi

  local start_ms now_ms deadline_ms
  start_ms="$(date +%s%3N)"
  deadline_ms=$((start_ms + ON_TOP_TIMEOUT_SEC * 1000))

  while true; do
    if wmctrl -l | grep -i "${RVIZ_WINDOW_HINT}" >/dev/null 2>&1; then
      wmctrl -r "${RVIZ_WINDOW_HINT}" -b add,above >/dev/null 2>&1 || true
      echo "[launch_with_trigger_0s] RViz set to always-on-top"
      return 0
    fi

    now_ms="$(date +%s%3N)"
    if (( now_ms >= deadline_ms )); then
      echo "[launch_with_trigger_0s] WARN: RViz window not found within ${ON_TOP_TIMEOUT_SEC}s"
      return 0
    fi

    sleep 0.3
  done
}

# Start launch first, then run helpers concurrently.
roslaunch --skip-log-check epic_planner "${MAP_NAME}.launch" use_gpu:="${USE_GPU}" &
LAUNCH_PID=$!

trigger_with_retry &
TRIGGER_PID=$!

set_rviz_on_top &
ON_TOP_PID=$!

cleanup() {
  if [[ -n "${LAUNCH_PID:-}" ]] && kill -0 "${LAUNCH_PID}" 2>/dev/null; then
    kill -INT "${LAUNCH_PID}" 2>/dev/null || true
  fi
  if kill -0 "${TRIGGER_PID}" 2>/dev/null; then
    kill "${TRIGGER_PID}" 2>/dev/null || true
  fi
  if [[ -n "${ON_TOP_PID:-}" ]] && kill -0 "${ON_TOP_PID}" 2>/dev/null; then
    kill "${ON_TOP_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

wait "${TRIGGER_PID}" || true

wait "${ON_TOP_PID}" || true
wait "${LAUNCH_PID}"
