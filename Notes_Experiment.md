# Notes Experiment

## 実装と実験の記録

### 環境
- Ubuntu 20.04 / ROS Noetic / conda (`epic_repro`)
- Python 3.8
- catkin workspace: `/home/robot/Research/Research_code/EPIC/EPIC`

### 実装変更の履歴
- `empy` を `3.3.4` に固定して catkin 生成エラーを解消。
- `lkh_tsp_solver` に `-fcommon` を追加してリンク時の multiple definition を解消。
- RViz は global theme ではなく local Qt stylesheet 方式に変更。
- RViz 関連の ROS パッケージ参照は `epic_planner` を使用。

### 実行コマンド（安定手順）
```bash
cd /home/robot/Research/Research_code/EPIC/EPIC
source /home/robot/anaconda3/etc/profile.d/conda.sh
conda activate epic_repro
source /opt/ros/noetic/setup.bash
source devel/setup.bash
export ROS_MASTER_URI=http://localhost:11311
export ROS_IP=127.0.0.1
roslaunch epic_planner garage.launch use_gpu:=false
```

### 実行コマンド（FINISH 到達で自動終了 + 指標保存）
```bash
cd /home/robot/Research/Research_code/EPIC/EPIC
./scripts/run_until_finish.sh garage
```

- 探索本体コードは非改変のまま、外側の実験ラッパーで終了判定する。
- `run_until_finish.sh` は起動時に 0s でトリガ送信を開始し、短時間リトライ（バースト送信）で起動同期ずれを吸収する。
- `run_until_finish.sh` は `trigger_callback_seen`（ログ中 `Triggered!` 検知）を保存し、`/planning/state == FINISH` 検知時は自動停止する。
- 実行結果は FINISH 到達時のみ `results/*_metrics.txt` と `results/*.log` に保存される。
- FINISH 以外の中断では metrics を残さず、必要なら `run_until_finish.sh` の `DEBUG_ONLY` コメントを一時的に外して確認する。

### 原著論文の評価指標と保存項目の対応
- 原著（arXiv:2410.14203v2）Table I の主要指標:
  - `Exp. Time (s)`
  - `Avg. Vel. (m/s)`
  - `Avg. Tm. (s)`
  - `Max. Tm. (s)`
  - `Exp. Fin.`
- `run_until_finish.sh` では上記に対応して以下を保存する:
  - `exp_time_sec`  ← `Exp. Time (s)`
  - `avg_vel_mps`   ← `Avg. Vel. (m/s)`
  - `avg_tm_s`      ← `Avg. Tm. (s)`
  - `max_tm_s`      ← `Max. Tm. (s)`
  - `exp_finished`  ← `Exp. Fin.`

### 補足（論文の他指標）
- Table II（ablation）は `Total Time Consumption (ms)`, `Total Path Length (m)` を比較している。
- 本ラッパーは `path_length_m` を保存するため、Table II の path length 比較の土台として使える。
- Table III は環境表現の `Memory Consumption (MB)` 比較。公開実装の通常ログからは厳密な同定が難しいため、補助値として `label_map_kb`/`label_map_mb` を記録する。
- `coverage` は原著 Table I の主要報告値ではなく、本文中の進捗可視化（Fig.5）で扱われる。厳密に揃えるには別途定義した評価スクリプトを固定する。

### 進捗
- `garage.launch` の継続実行を確認。
- `Plan Global Path` と `cloud odom callback` の定常ループを確認。
- `wait for trigger.` は待機状態の警告として運用可能。

### 現時点の検証チェックポイント
- ノート上の指標対応は Table I 主要指標と 1 対 1 で対応済み。
- 実行時は `results/*_metrics.txt` に paper-aligned 指標と補助指標を同時保存する。
- 再現性担保のため、探索本体コードは非改変のまま外部ラッパーのみで終了判定と保存を行う。
- `WAIT_TRIGGER` は設定で無効化できず、初回トリガは運用で即時送信する前提。

### 最新の実測（3チェックポイント）
- 実行A: `FINISH_TIMEOUT_SEC=60 TRIGGER_TIMEOUT_SEC=10 ./scripts/run_until_finish.sh garage`
  - 生成物: `results/garage_20260529_225349_metrics.txt`, `results/garage_20260529_225349_runtime_stats.txt`, `results/garage_20260529_225349.log`
  - トリガ受理: `trigger_callback_seen=true`, `trigger_attempts=2`, `trigger_ack_sec=16.391`
  - FINISH終了: `finish_detected=false`, `exp_finished=false`, `finish_wait_exit_code=124`
  - 評価指標出力: `exp_time_sec=60.449`, `avg_vel_mps=3.861`, `avg_tm_s=0.037189`, `max_tm_s=0.064838`
- 実行B: `FINISH_TIMEOUT_SEC=180 TRIGGER_TIMEOUT_SEC=10 ./scripts/run_until_finish.sh garage`
  - 生成物: `results/garage_20260529_225742_metrics.txt`, `results/garage_20260529_225742_runtime_stats.txt`, `results/garage_20260529_225742.log`
  - トリガ受理: log に `Triggered!` と `[triggerCallback]: from WAIT_TRIGGER to PLAN_TRAJ` を確認、`trigger_callback_seen=true`
  - FINISH終了: `finish_detected=false`, `exp_finished=false`, `finish_wait_exit_code=124`
  - 評価指標出力: `exp_time_sec=180.456`, `avg_vel_mps=2.651`, `avg_tm_s=0.049388`, `max_tm_s=0.085105`

## トラブルシューティング

### 1) `no odom` が続く / 探索が進まない
- 症状: launch は開始するが探索が進まない。
- 確認: map ファイル配置。
  - `src/MARSIM/map_generator/resource/garage.pcd`
  - `src/MARSIM/map_generator/resource/cave.pcd`
  - `src/MARSIM/map_generator/resource/factory.pcd`

### 2) GPU/OpenGL 依存の不安定さ
- 症状: MARSIM の挙動が不安定。
- 対応: まず CPU モードで起動。
  - `roslaunch epic_planner garage.launch use_gpu:=false`
- 追加確認: `nvidia-smi`, `glxinfo | grep OpenGL`

### 3) cloud-odom 同期が弱い
- 症状: callback が十分に発火しない。
- 対応: `cloud_odom_sync_queue` を scenario yaml で調整。
  - `src/global_planner/exploration_manager/config/garage.yaml`
  - `src/global_planner/exploration_manager/config/cave.yaml`
  - `src/global_planner/exploration_manager/config/factory.yaml`

### 4) 環境読み込み順の崩れ
- 症状: launch 失敗や挙動不一致。
- 対応: 上記の実行コマンド順を厳守。

### 5) timeout 終了コード
- `124` は timeout による終了であり、起動失敗とは限らない。
- 確認: `~/.ros/log` と `rosnode list` を併用する。
