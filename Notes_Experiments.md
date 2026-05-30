# Notes Experiments

## 目的
- 実験進捗、再現手順、トラブルシューティング、結果比較を 1 ファイルに集約する。
- 先行研究（arXiv:2410.14203v2, Table I）の値と自前実測値を同じ表形式で管理する。

## 現在の状態（2026-05-30）
- 探索本体コードは非改変、実験ラッパー `scripts/run_until_finish.sh` で運用。
- FINISH 到達時のみ metrics を保存する方針を適用。
- FINISH 到達時に `results_csv/` の表ファイルへ自動追記する仕組みを導入。

## 主要成果物
- 実行ログ: `results/<map>_<run_id>.log`
- FINISH 実行メトリクス: `results/<map>_<run_id>_metrics.txt`
- 実行中統計: `results/<map>_<run_id>_runtime_stats.txt`
- 実験テーブル（自動更新）:
  - `results_csv/run_metrics_table.tsv`
  - `results_csv/paper_vs_run_table.tsv`
  - `results_csv/paper_table_i_reference.tsv`

## 直近の比較（Garage）
- 先行研究 Table I (Proposed, Garage):
  - `Exp. Time=716.9`, `Avg. Vel=3.10`, `Avg. Tm=0.05`, `Max. Tm=0.10`, `Exp. Fin=true`
- 自前実測（run_id=20260530_003626）:
  - `Exp. Time=720.480`, `Avg. Vel=3.320`, `Avg. Tm=0.060900`, `Max. Tm=0.121249`, `Exp. Fin=true`
- 差分:
  - `+3.580s`, `+0.220m/s`, `+0.010900s`, `+0.021249s`

## 次に試す実行コマンド（garage以外）
```bash
cd /home/robot/Research/Research_code/EPIC/EPIC

# cave
FINISH_TIMEOUT_SEC=1800 TRIGGER_TIMEOUT_SEC=10 ./scripts/run_until_finish.sh cave

# factory
FINISH_TIMEOUT_SEC=1800 TRIGGER_TIMEOUT_SEC=10 ./scripts/run_until_finish.sh factory
```

## 連続実行（おすすめ）
```bash
cd /home/robot/Research/Research_code/EPIC/EPIC
for map in cave factory; do
  FINISH_TIMEOUT_SEC=1800 TRIGGER_TIMEOUT_SEC=10 ./scripts/run_until_finish.sh "$map"
done
```

## 推奨テーブル設計
- 行: 1 実行 1 行（`run_id` を主キー）
- 列: 実験条件 + 評価指標 + 参照差分
  - 条件: `map`, `launch_file`, `scenario_yaml`, trigger/timeouts
  - 指標: `exp_time_sec`, `avg_vel_mps`, `avg_tm_s`, `max_tm_s`, `exp_finished`, `path_length_m`
  - 比較: `paper_*`, `delta_*`, `delta_*_pct`

## トラブルシューティング
- `plan success: new traj pub` は通常の再計画成功ログで、FINISH ではない。
- `Ctrl+C` で誤停止しやすい場合:
  - 現在は FINISH 前の Ctrl+C を無視する設定を導入済み。
  - 強制停止は SIGTERM を使う。
- timeout `124` は「時間切れ」であり、起動失敗とは別。
- 終了時に後処理例外が出ても、metrics が先に保存されていれば結果は有効。

## 備考
- `factory` はコード上 map 名、先行研究 Table I は `campus` 表記。比較表ではこの対応を明記して扱う。
