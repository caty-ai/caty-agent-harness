# L1-9 上流レビュー r1 裁定 — #159 overflow sentinel 設計 v0.2

2026-08-23 / 裁定者= Alpha（writer・票には数えない） / 対象= DESIGN-159-overflow-sentinel-DRAFT.md v0.2
席= loom-seats 決定論算出（size H・risk なし・--absent qwen3.8-max fable-5 opus-5・GO・
opus は writer=Alpha と同系統のため例外記録を作らず欠席指定で回避）。
全席 fresh context / read-only / 資料同梱方式（brief-common.md + 証拠4本 ≈31KB）。
生存確認= 3席とも起動前 PONG 実測。coverage-matrix= Kimi 席に添付（spec-kit 台帳 row12 記載）。

## 席と評定

| 席 | requested | actual（自己申告） | verdict | blocking |
|---|---|---|---|---|
| GLM | glm-5.3（wrapper 既定・effort high） | 明示節なし（出力は日本語・GLM 経路実測） | GO-with-concerns | MAJOR 3 |
| Kimi | kimi-k3（kimi CLI 既定） | 「Kimi (Moonshot AI)・版数非開示」 | **NO-GO**（狭い・v0.3 で解消可・delta 再レビューで足りる） | MAJOR 3 |
| Grok | grok-4.6（grok CLI 既定） | 「Grok 4.6 (xAI)」 | **NO-GO** | MAJOR 5 |

総合裁定: **設計 v0.3 改訂が実装開始の前提**（2 NO-GO + 1 GWC）。全席が「骨格と D1〜D5 の
実行は正しい・方針のやり直しは不要・文書レベルの確定で GO を取りうる」で一致。
再レビューは変更節の delta（Kimi 明示・他席も同型）。

## 採用 findings（v0.3 反映リスト・収束順）

- **F1（3席収束・GLM#1/Kimi#1/Grok#1）発火述語の一意化**: v1 の観測量を「ターン完了 usage の
  `injected = input + cache_read + cache_creation`（正味・排他加算を tap 契約に明記）の
  N 移動平均 + 傾き」に凍結。送信直前の点推定は v2 へ降格（runtime フック可否がランタイム毎に
  未確定のため。Grok の指摘: 列挙済み取得元は全てターン完了後で、Hermes 位置の判定は現 tap では
  物理的に不可能）。結合規則を1文で規定: `fire if MA(injected,N) > 水位閾値 OR slope が M ターン内到達を射影`。
  ターン1〜2 の縮退規則も明記。
- **F2（2席収束・Kimi#3/Grok#2）絶対トークン閾値の併置**: 水位を二本立てに —
  絶対 `injected > T_abs`（既定 40k 近傍・EV-006 の harness 上界由来）OR 相対 `> w×ctx_window`
  （あふれ射影用）。1M 窓で相対のみだと浪費帯 112k/turn が 11% で永遠に発火しない盲点を塞ぐ。
  EV-007 sweep に T_abs（30k/40k/80k）を追加。
- **F3（3席収束・GLM#2/Kimi#2/Grok#5）EV-007 事前登録の凍結**: 別紙化して以下を freeze —
  誤発火/見逃しの運用定義（`completed` を真陰性に使わない・コスト反実仮想で判定）/
  強制オーバーフロー副腕（config 上書きで窓を 64k に人工縮小・Kimi 案）/ モデル別仮説と
  非劣性マージン（haiku=完遂率・sonnet=トークン比・codex=発火率0 制約）/ 分解者 B/C は入れ子で
  n 別建て / qwen on claude CLI（検索型モデル×全読み込みランタイム）の一般化腕1本（Grok 案）/
  窓ロック（qwen=262144）等の env 凍結 / auto-enqueue 腕には mid-task handoff 契約を §5 に新設。
- **F4（3席収束・GLM#3/Kimi D-5/Grok#4）TTFB 軸の作用面を alert-only に**: v1 の watchdog は
  検出+ログ+alert のみ（kill しない・step timeout は現行のまま）。所有境界を明文化 —
  #162= 事後の attempt 分類・早期 DLQ / sentinel 軸3= 生検出+alert。共有は byte tap のみ。
  SSE ping を first byte に数えない条項・reasoning floor 未収載モデル（GLM 前例）の unknown 方針を表に追加。
- **F5（Grok#3/GLM#2e/Kimi D-4 収束）発火ログの分離と充実**: `fire` と `task_end` を別イベント化
  （in-place 追記をやめる）。`axis: level|slope|both|alert`・`nudge_disposition`・`tap_status`・
  `started_at`・推定/実測の別・総トークン（ledger 結合キー）を追加。置き場は task-runner ledger への
  合流を第一候補に再検討（Grok）。
- **F6（非ブロッキング採用）**: cache_read 語彙のランタイム差（codex/agy）の正規化規則 /
  auto-compaction イベントで MA リセット+保留 nudge 抑制 / class prior は v1 を unknown-only に
  縮退（search prior は明示オプトイン・Qwen の「runtime≠挙動」問題を回避）/ ctx_window の
  出所フィールドをログに / スキーマ版数 / Issue の Files-to-touch を D1=B に合わせ core 側へ訂正。

## 不採用・保留

- GLM「HF config.json は訓練上限で提供窓と異なりうる」→ 採用（F6 の出所フィールドで対応）だが
  梯子の順位は維持（過大方向は Kimi F2 の絶対閾値併置で無害化）。
- ログ強化のうち HTTP status / リクエストサイズ推定（Grok D-4）は v1 必須にしない（同席自身が v1 非必須と明記）。

## 次の手順

1. Alpha が v0.3 改訂（F1〜F6 反映・EV-007 事前登録を別紙 `EV007-PREREG-DRAFT.md` に分離）
2. 変更節の delta 再レビュー（同3席・CUMULATIVE 評定）
3. GO 後: EV-007 事前登録の翔さん決裁 → 実装（Codex 委譲）
