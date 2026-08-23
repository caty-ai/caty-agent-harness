# L1-9 delta 再レビュー r2 裁定 — DESIGN v0.3 + EV007-PREREG v0.1

2026-08-23 / 裁定者= Alpha（writer・票に数えない）
正席（票）= kimi-k3 / grok-4.6 / glm-5.3（r1 と同一・fresh context・r1 裁定同梱の delta 方式）
参考（傍証・票に数えない）= codex-sol（実行中→着次第追記）/ fable-5（writer 同一モデル・盲点申告つき）/
opus-5[1m]（writer 同系統・統計監査重点）— 翔さん依頼 2026-08-23。out ファイル= reviews-159-L19/out-*-r2.md

## 評定

| 視点 | verdict | F1-F6 |
|---|---|---|
| GLM（正席） | NO-GO（狭い・prereg のみ） | F1/F2/F4/F5/F6 RESOLVED・F3 PARTIAL |
| Grok（正席） | **GO-with-concerns**（機構は実装可・凍結前に要修正） | F1/F2/F4/F5/F6 RESOLVED・F3 PARTIAL |
| Kimi（正席） | NO-GO（狭い・prereg レベル） | 同上（F5 に軽微欠落） |
| Fable（参考） | GO-with-concerns | F5 PARTIAL 指摘+橋渡し条項 |
| Opus（参考） | 設計=GWC / prereg=条件付き NO-GO | F1 PARTIAL（slope 未凍結）・F3/F5 PARTIAL |

**総合裁定: DESIGN は v0.4 の小修正・EV007-PREREG は v0.2 へ実質改版。その後 r3 delta（3正席・
変更点のみ）で CUMULATIVE GO を確認してから翔さん決裁③へ。**

## 採用リスト（v0.4 / prereg v0.2 反映）

### 3席収束（blocking）
- **A1 誤発火定義の修正**（GLM B2 / Kimi B1 / Grok#2）: 比の向きの曖昧さで最悪ケース（発火して5x燃焼）が
  除外される逆転を排除。新定義= false fire は「必要性の反実仮想」のみ（fired ∧ bare 硬あふれ無し）で数え、
  cost 比（両方向を明記した式で）により harmless / harmful を層別報告。
- **A2 sweep 選定規則の再構築**（3席 + Kimi 再採点案 + Opus B4 replay 案を統合）: 較正はライブ 6本を廃止し、
  **主グリッドの bare/shadow 系列への (T_abs,w) 全格子オフライン replay** に置換（循環解消・実質 n 増・
  6本削減）。目的関数は両側化（codex/qwen 発火率0 かつ harmful false-fire 率 ≤ 閾値の制約下で sonnet
  トークン比最小化）。replay 妥当性は非介入腕の系列に限る旨明記。採用値での codex 確認セル1本を残す。
- **A3 mid-task handoff 契約の新設**（GLM B1 / Kimi B3 / Grok#4）: 最小契約を prereg に定義 —
  fire はターン完了後 → 当該ターンは完走済み → auto-enqueue は封緘計画を fresh context で先頭から・
  depth 1・workspace 成果物は残置・re-fire 禁止。v1 出荷（nudge のみ）とは別物である旨を橋渡し条項（A4）で接続。

### 参考枠からの採用（blocking 相当）
- **A4 橋渡し条項**（Fable#2）: 本実験がライセンスするのは「発火タイミングの質」。nudge-only の従属率は
  v1 運用ログで事後観測し、default-on 判定は発火タイミングの質と codex/qwen 無発火に依存する、と prereg に明記。
- **A5 slope の凍結**（Opus B1）: `slope = (MA_t − MA_{t−K})/K, K=3`・`projection_turns = (ctx_window −
  MA_t)/slope (slope>0)`・`≤ M=10 で発火`。T_abs/w とも比較対象は MA（Kimi N5 も同旨）。
- **A6 影評価（shadow）**（Opus B2）: 全腕で tap+判定を走らせ nudge を抑止（`nudge_disposition: shadow`）。
  per-turn `injected` 系列を ledger に必須保存（replay と miss 判定の材料）。miss は bare/shadow 系列で判定可能になる。
- **A7 hard_overflow の分離**（Opus B3）: `window_error`（API 拒否）/ `runtime_compaction`（ランタイム申告）/
  `compaction_suspected`（ヒューリスティック）に分割。**miss の主定義は window_error**。64k 副腕の飽和を回避。
- **A8 判定手続きの凍結**（Opus B5 + Grok#7 + Fable 非ブロッキング）: エンドポイントに confirmatory /
  descriptive ラベル。確証= codex/qwen の per-turn 発火率（分母=総ターン・rule of three 併記）と対応つき
  トークン比（ペア幾何平均・全ペア中央値）。haiku 完遂率・正答非劣性・副腕2 B/C は descriptive（n 粒度が
  マージンより粗いため）。**統合規則を1文で凍結**: default-on GO の必要条件= codex 発火率0 ∧ sonnet
  トークン比ペア中央値 < 1.0 ∧ harmful false-fire が全ペアで一貫悪化しないこと。B/C は記述のみ・v2 の
  宛先変更は「完遂率差 ≥ +2/8 が両モデルで同方向」の下限つき。

### 設計側の細部（採用）
- axis に `both` 復活・`threshold_hit: abs|ratio|both`・`started_at`・「推定/実測の別」・run_meta
  （arm/seed/shuffle_seed/適用パラメータ）を fire/task_end/turn 系列に追加（Kimi N1-2 / Grok#5-6 / Opus NB5）。
- **alert は fire と別イベント**（Grok#5: codex の「発火0」判定を TTFB alert が汚染しないように）。
- ナッジのヒステリシス（Fable）: nudge はタスクごと軸ごと1回・再提示は水位が一段上のバンドを跨いだ時のみ。
- §4 の説明修正（Opus NB1）: OR の実効閾値は min(T_abs, w×W) — 窓 ≥80k では絶対項が常に先に効く、を
  正文化。w sweep の主グリッド感度ゼロ → 削減メニュー最上位の根拠に昇格。
- T_abs の系譜注記（Fable）: EV-006 の 20-40k は per-step 注入・sentinel の injected は累積 — レジーム差を
  §5 由来欄に明記し、replay 較正の候補を {40k, 80k, 120k} に広げる（40k 過敏側の懸念を較正で受ける）。
- 削減メニュー矛盾の修正（Opus NB2）: p2-L を落とす場合は sonnet 基準を M 帯へ読み替え+閾値再設定を併記。
- false-fire 対照のペアリング（Opus NB3 / Fable）: 対照= 同一 (model, task) の bare 全 seed 幾何平均。
- TTFB 床の tier キー（Kimi N4）: 前ターンの injected を使用、byte イベントに optional size を追加。
- miss の lead を ≥1 / ≥3 の2本報告（GLM 非ブロッキング5）。DLQ 再走フラグ+感度分析（Opus NB8）。
  実行時刻・モデル版スタンプ（Opus NB7）。較正≠効果推定の1文（Opus NB6）。tap 適合 golden-file テストを
  実装 Issue の Done when へ（Fable）。compaction の二面性の相互参照1行（Fable）。
  reasoning floor 表の実体収載（GLM/Grok）。課題名の表記ゆれ解消（GLM 非ブロッキング7）。

### 不採用・保留
- 1M 窓モデルの sweep 追加（Fable 非ブロッキング）→ v2 ロードマップの追試予約に留める（費用対効果）。
- Kimi N3（w レンジが定常値 56% 未満で sonnet に常時発火）→ NB1 採用により w は主グリッド感度ゼロ・
  replay で {40-70%} を無料で振れるため、レンジ拡張は replay 側で吸収。

## 次の手順
1. Alpha: DESIGN v0.4（slope 凍結・alert 分離・スキーマ増補・説明修正・ヒステリシス）+
   EV007-PREREG v0.2（shadow・replay 較正・overflow 分離・判定手続き凍結・橋渡し条項・handoff 契約）
2. r3 delta（3正席・変更点のみ・CUMULATIVE 評定）
3. GO 後: 翔さん決裁③（本数は replay 採用で 68→**62本 + smoke 2** に減）
