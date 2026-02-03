# Kuyu Implementation Plan — v2.4

## 目的
Manasの学習と評価のため、swappability/HFストレスに強い訓練世界を実装する。

## 実装フェーズ
### 1) イベント注入
- Sensor swap / Actuator swap / HF stress の定義と実装
- Seedとログに完全反映

### 2) 訓練ループ
- DriveIntent + Reflex corrections → DAL → Actuator の統合経路
- 監視指標（HF/回復/過渡/違反）をログ化

### 3) M1‑ATT スイート
- 姿勢制御に限定した最小カリキュラムを構築
- 成否判定と回復時間の自動評価

### 4) MLX 学習データ出力
- SimulationLog から JSONL データセットを生成
- meta/records のフォーマットを固定化

### 5) UI 統合
- ContentView = 実行環境（Previewも同一経路）
- Terminalに全エラー/警告を集約
- Reflex/Gating/Trunksの可視化を追加
