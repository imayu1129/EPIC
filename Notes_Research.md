# Notes Research

## 研究目的
- EPIC を Ubuntu 20.04 + ROS Noetic 環境で安定再現し、探索アルゴリズム評価を継続可能にする。
- 実装変更と運用手順を整理し、再実験の立ち上げ時間を短縮する。

## 研究の進め方
- まず再現性を優先し、環境差分の吸収を行う。
- 次に可視化と実行安定性を整え、評価観点を固定する。
- 最後にログ観測を定常化し、設定変更の効果を比較可能にする。
- 先行研究の公開コードに準拠し、探索本体のコードパスは変更しない。
- 運用自動化が必要な場合は、公開コードの外側（起動コマンド/実験手順）で実施する。

## 現在の進捗
- `catkin build` が通る状態を維持できている。
- `epic_repro` 環境で `garage.launch` の継続実行を確認済み。
- RViz は局所スタイルシート方式で UI 調整済み。
- ループログ (`Plan Global Path`, `cloud odom callback`) は継続して観測できている。
- `wait for trigger.` は待機系ログとして扱えることを確認済み。
- `WAIT_TRIGGER -> PLAN_TRAJ` の遷移（トリガ受理）は再確認済み。
- 現在の bounded 実行（60s/180s）では `FINISH` 到達前にタイムアウトするケースを確認しており、`FINISH` 自動停止は map/条件ごとの追加検証を継続中。
- 実験ラッパー `scripts/run_until_finish.sh` で FINISH 自動停止と結果保存を実施できる状態を整備済み。
- 原著 Table I 主要指標に合わせた保存項目 (`exp_time_sec`, `avg_vel_mps`, `avg_tm_s`, `max_tm_s`, `exp_finished`) を運用手順に組み込み済み。
- 可視化は RViz 地図表示と First Person 表示（`image_view`）の同時起動を launch 側で実装済み。
- `WAIT_TRIGGER` は設定でスキップできず、`fast_exploration_fsm.cpp` 側で `INIT -> WAIT_TRIGGER` がハードコードされている。

## 最新検証メモ（2026-05-29, garage）
- 検証1: トリガがちゃんと入っているか（何秒か）
	- 実行ログ `results/garage_20260529_225742.log` で `Triggered!` と `[triggerCallback]: from WAIT_TRIGGER to PLAN_TRAJ` を確認。
	- 指標 `results/garage_20260529_225742_metrics.txt` に `trigger_callback_seen=true`, `trigger_attempts=2`, `trigger_ack_sec=16.350` を記録。
- 検証2: FINISH でちゃんと終わるか
	- `FINISH_TIMEOUT_SEC=60` および `180` の bounded run では未到達。
	- `results/garage_20260529_225349_metrics.txt` と `results/garage_20260529_225742_metrics.txt` はともに `finish_detected=false`, `exp_finished=false`, `finish_wait_exit_code=124`。
- 検証3: 評価指標はちゃんと出るか
	- `results/garage_20260529_225349_metrics.txt` と `results/garage_20260529_225742_metrics.txt` の生成を確認。
	- Table I 対応の主要項目（`exp_time_sec`, `avg_vel_mps`, `avg_tm_s`, `max_tm_s`, `exp_finished`）を出力できている。

## 実装面の要点
- `empy==3.3.4` 固定で ROS 生成系エラーを回避。
- `lkh_tsp_solver` で `-fcommon` を追加し多重定義エラーを回避。
- map ファイル (`garage/cave/factory.pcd`) 配置を前提条件として明示。
- RViz 起動で ROS パッケージ名 `epic_planner` を使用。

## トリガ運用方針（先行研究準拠）
- GitHub の公開手順には「RViz の `2D Nav Goal` でトリガする」ことは明記されている。
- 一方で、トリガ入力の厳密な待機時間（起動後何秒で押すか）は明記されていない。
- 再現実験では「起動後 0s（即時）で初回トリガを入れる」を標準手順とする。
- ただし探索本体コードは変更せず、初回トリガの自動入力は起動コマンド側で行う。
- 起動同期ずれを吸収するため、運用上は「0sで送信開始 + 短時間リトライ（バースト送信）」を採用する。
- 設定だけで `WAIT_TRIGGER` を省くことはできないため、必要なら起動側で自動トリガする運用を使う。

### 起動直後の自動トリガ（コード非改変）
```bash
cd /home/robot/Research/Research_code/EPIC/EPIC
source /home/robot/anaconda3/etc/profile.d/conda.sh
conda activate epic_repro
source /opt/ros/noetic/setup.bash
source devel/setup.bash

# 起動後 0s（即時）に 1 回だけ初回トリガを送る（公開コードは非改変）
(sleep 0; rostopic pub -1 /move_base_simple/goal geometry_msgs/PoseStamped "{header: {frame_id: 'world'}, pose: {position: {x: 3.0, y: 0.0, z: 1.0}, orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}}}") &
roslaunch epic_planner garage.launch
```

## 次の研究タスク
- Table I/II/III の比較表に投入するため、map 別に複数回実行して統計量（平均/分散）を固定フォーマットで集計する。
- Table III の `Memory Consumption (MB)` について、ログ由来値 (`label_map_mb`) と論文定義との差分を明文化する。
- 実カメラ系 topic が利用可能な場合は First Person 表示 topic を差し替え、可視化条件を統一する。

## 最新アップデート（2026-05-30）
- `garage_20260530_003626` で FINISH 到達を確認（`exp_finished=true`）。
- 最新実測値: `exp_time_sec=720.480`, `avg_vel_mps=3.320`, `avg_tm_s=0.060900`, `max_tm_s=0.121249`。
- 先行研究（Table I, Garage/Proposed）との差分は `+3.580s`, `+0.220m/s`, `+0.010900s`, `+0.021249s`。
- `scripts/run_until_finish.sh` に FINISH 時の自動集計を追加済み。
	- `results_csv/run_metrics_table.tsv` に全実験行を追記。
	- `results_csv/paper_vs_run_table.tsv` に先行研究比較行を追記。
	- `results_csv/paper_table_i_reference.tsv` を参照値として自動初期化。
- Ctrl+C 誤停止対策を導入済み（FINISH 前は Ctrl+C を無視、終了は FINISH 優先）。
- 可視化調整を反映済み。
	- 背景色: 黒。
	- Grid: OFF（色も黒に統一）。
	- `explore_env/buffered_cloud`: `Style=Flat Squares`, `Size(m)=0.05`, `Alpha=0.1`, `Min/Max=0/10`。
	- `debug_info/current_frame/well_observed`: `Color=239;41;41`。

## トラブルシューティング追記
- `plan success: new traj pub` は FINISH ではなく、通常の再計画成功ログ。
- `check traj velocity failed` は一時的に再計画失敗を出しても、直後に復帰することがあるため遷移全体を見る。
- 後処理で `boost::lock_error` が出る場合があるが、FINISH後に metrics が書けていれば結果は有効。
- 誤停止を避けるため、長時間実験の監視コマンドは別ターミナルで実行する。
