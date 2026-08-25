r3 の最終確認レビューとして、まず埋め込み全文と r2 裁定を読み、A1–A8 の解消と新規欠陥の有無だけを検証します。A1–A8 を条文単位で突き合わせました。結論は狭い NO-GO です。A2 の選定制約が、同じ紙の replay データから計算できない内部矛盾を残しています。

## Verdict

**NO-GO**（狭い。対象は EV007-PREREG v0.2 の A2 選定規則だけ。DESIGN v0.4 の機構凍結は実装可能な水準）。CUMULATIVE GO にはしない。決裁③に進む前に、下記 New blocking 1件を replay で計算できる量に直す必要がある。

| ID | 裁定要求 | r3 判定 | 根拠 |
|---|---|---|---|
| **A1** | false-fire = 必要性の反実仮想。比の向きを明示し harmless/harmful 層別 | **RESOLVED** | §1: `fired ∧ 対照 bare に window_error 無し` を necessity-false-fire とし、`cost_ratio = tokens(sentinel) / geomean(bare 同一 model×task 全 seed)`。`< 1.0` = harmless、`≥ 1.0` = harmful。発火+completed は定義に使わない。5x 燃焼は harmful に入る。 |
| **A2** | ライブ sweep 廃止。非介入系列へのオフライン replay。両側制約＋目的。採用値で codex 確認セル | **PARTIAL** | ライブ6本廃止・格子 `{40k,80k,120k}×{40%,50%,60%}`・非介入に限る旨・確認セルの骨格は入った。しかし選定**制約**の `harmful 率` は §1 定義では sentinel 実測トークンが要り、同じ節が「分解コストは推定しない」と書いており、replay 上で実行不能。下記 New blocking。 |
| **A3** | mid-task handoff 最小契約 | **RESOLVED** | §3: 発火ターン完走済み、封緘計画を fresh context で先頭から、depth 1、re-fire 禁止、成果物残置、採点から発火前成果物除外、`total_tokens = 親（発火まで）+ 全子`、`parent_id` で機械集計。 |
| **A4** | 橋渡し条項（測るのは発火タイミングの質。nudge 従属率は v1 運用ログ。default-on はタイミング＋無発火） | **RESOLVED** | §0 が独立節。nudge 効果への読み替えを明示禁止。v1 出荷（nudge のみ）と実験特例（auto-enqueue ON）を切断。 |
| **A5** | `slope = (MA_t − MA_{t−K})/K, K=3`、射影、`≤ M=10`、level の比較対象は MA | **RESOLVED** | DESIGN §4 の一意述語ブロックに式・`slope>0` のみ定義・未取得なら未定義＝不発火が凍結。実効閾値 `min(T_abs, w×W)` と「窓≥80k では絶対項が先」も正文化。縮退の一文だけが式と食い違う（非ブロッキング）。 |
| **A6** | 全腕 shadow。nudge 抑止。per-turn injected を ledger 必須 | **RESOLVED** | prereg §1 全腕 tap+判定、bare/always-harness は `nudge_disposition: shadow`。DESIGN §6 は turn を毎ターン保存し、要約だけでは lead を復元できないと明記。 |
| **A7** | `window_error` / `runtime_compaction` / `compaction_suspected` 分離。miss の主定義は window_error | **RESOLVED** | task_end スキーマと prereg §1。miss は bare/shadow 系列、lead ≥1 と ≥3 の2本。runtime_compaction は記述のみ。64k 副腕で相対項が実効になる旨あり。 |
| **A8** | confirmatory/descriptive ラベル。統合規則1文 | **RESOLVED** | §4 表＋「codex 発火率0 ∧ sonnet 全ペア中央値 < 1.0 ∧ harmful false-fire が全ペアで一貫して発生しない」。haiku・副腕2は GO を覆さない。B/C の v2 変更は `C−B ≥ +2/8` が両モデル同方向。rule of three、ペア幾何平均、分母=総ターン、較正≠効果推定はいずれも入っている。 |

DESIGN 側の r2 採用細部（alert≠fire、`axis/threshold_hit` の `both`、`started_at` / `value_kind` / `run_meta` / `schema_version`、ヒステリシス、T_abs 系譜、p2-L 削減時の読み替え、golden-file、TTFB の前ターン injected）は、alert のフィールドが fire より薄い点を除き入っている。

---

## New blocking findings

Ratchet: 埋め込み条文の実行不能または内部矛盾のみ。D1–D5 の再審理なし。既に non-blocking と裁定された指摘の蒸し返しなし。

### NB-r3-1. A2 選定制約の `harmful 率` は、指定した replay データから計算できない

prereg §1 は harmful を次で定義している。

`cost_ratio = tokens(sentinel腕 run) / geomean(tokens(bare 同一 model×task 全 seed))`  
`cost_ratio ≥ 1.0` → harmful

§2 の選定規則は、その harmful 率 ≤ 10% を **replay 上の制約** に置いている。同じ箇条書きは、replay について「発火した run に分解が入った場合の推定ではなく」と書いており、妥当性は「非介入腕の系列に限り」と制限している。

非介入の bare/shadow 系列には sentinel 腕の `tokens(sentinel腕 run)` が無い。したがって §1 の harmful は replay の入力から識別できない。ライブ sweep を replay に置換した時点で、制約側を replay で観測できる量（例: necessity-false-fire **率**、または早すぎ発火率）に置き換える必要があった。目的関数だけタイミング指標に置換し、制約はライブ専用の cost_ratio のまま残している。

この穴が残ると、(T_abs, w) を機械的に選べない。実装者が harmful を別定義すれば、それは事前登録した選定規則ではなくなる。A2 のゲート（両側選定が実行できること）を満たしていない。

**閉じ方（例。ここから先は指摘であり、採択は writer の範囲）:** 制約から `harmful` を外し、replay で識別できる量だけにする。候補は (i) necessity-false-fire 率 ≤ 閾値、(ii) 早すぎ（fire 時 injected ≤ 最終の 50%）率 ≤ 閾値。harmful 層別はライブの sentinel 本走と A8 統合規則に残す。実行不能時（実行可能集合が空）の手続きも1行で凍結する。

---

## Non-blocking findings

凍結を止めない。パッチ推奨。再レビューの対象にしない。

1. **A5 縮退文が式と衝突**  
   一意述語は `t−K` 未取得なら slope 未定義。K=3 なら最初の slope は MA_1 が存在するターン4。直後の「傾きはターン2から」は K=1 の残骸。実装は「唯一の定義」ブロックに従えば一意。当該文を「MA_{t−K} が取れてから（K=3 なら t≥4）」に直す。

2. **replay 母数「48本」と非介入限定の併記**  
   主グリッド48本のうち非介入は bare 16 + always-harness 16 = 32。sentinel 16 本の発火後系列は介入済みで、ここに格子を当てると A2 が潰した循環が戻る。「48本のうち非介入 shadow 系列のみ」と書く。always-harness 系列は水位レジームが違うので、既定値の採用母集団を bare に限るか、感度分析に落とすかを明示した方がよい。

3. **確認セルが条件付き / 実行順が未凍結**  
   r2 は「採用値での codex 確認セル1本を残す」。v0.2 は既定 (40k, 50%) と異なるときだけ。本走 sentinel が較正の前か後かも書いていない。較正後の値で sentinel を走らせないと、A8 の sonnet トークン比は出荷既定と別物になる。推奨順: 非介入収集 → replay で (T,w) ロック → その値で sentinel（と、採用値が既定でも codex 1本）。「較正≠効果推定」は replay 指標を効果と呼ばない、の意味に読めば A8 と両立する。

4. **タイミング指標の分母**  
   「50–90% 帯の run の割合」の分母が全 run か発火 run か未指定。未発火を「遅すぎ」に入れるかどうかで選定が変わる。

5. **DESIGN §6 の誤発火文が古い**  
   「誤発火の定義はコストで行う」は A1 の necessity-first と読みがずれる。正本は prereg §1 と1行で指せば足りる。

6. **DESIGN §7 がまだ「w と T_abs の sweep」**  
   正本は replay。骨子の更新漏れ。

7. **削減メニューの 0.6→0.8**  
   現行の努力目標は既に `< 0.8`、GO は `< 1.0`。0.6 は v0.1 の数字。p2-L を落とすときは努力目標の扱い（維持 / 撤廃）だけ書けばよい。

8. **qwen を confirmatory としつつ GO 中立**  
   統合規則（凍結文）に qwen は入っていないので A8 どおり。表の「外れたら prior に差し戻し」と「GO 中立」は、差し戻し先が search-prior 設計であって default-on ではない、と読めば矛盾しない。その旨を表脚注に1行。

9. **alert スキーマが fire/task_end より薄い**  
   `schema_version` はある。`started_at` / `run_meta` は無い。結合キー `task_id` で足りる。Grok r2#5 の本旨（発火0判定を TTFB が汚染しない）はイベント分離で満たしている。

10. **`threshold_hit` と `min()` の対応**  
    述語は単一比較 `MA > min(T_abs, w×W)`。`abs|ratio|both` は「どちらの個別境界を超えたか」（`MA>T_abs` と `MA>w×W`）と定義すれば一意。min のどちらが binding だったかの記録とは別。

11. **miss は confirmatory だが統合規則に入らない**  
    A8 の凍結文は3条件のみ。表は `miss 0/観測数を報告` で、合格条件ではなく報告様式。n=2 の点推定と明記してある。意図どおりなら「GO ゲートではない」と脚注。

12. **本数**  
    算術 48+4+8+1条件 = 60〜61 + smoke 2 は正しい。r2 裁定の「62本 + smoke 2」は概数。不一致ではない。

---

## Model identity

- **Seat:** grok-4.6（r1 / r2 と同一正席）
- **Provider:** xAI
- **Mode:** L1-9 delta r3、READ-ONLY、埋め込み3点（ADJUDICATION-r2 / DESIGN v0.4 / EV007-PREREG v0.2）のみ。外部参照なし
- **Scope respected:** A1–A8 の解消確認と、改版が持ち込んだ実証欠陥。D1–D5 および r2 で non-blocking とされた項目は再審理していない
- **r2 自票との関係:** r2 は GO-with-concerns（機構は実装可、凍結前に修正）。r3 で DESIGN 側の凍結（A5/A6/A7 とスキーマ）は閉じた。残欠は prereg A2 の選定制約が replay で識別できない1点。そのため CUMULATIVE GO ではなく狭い NO-GO

パッチ後に見るのは NB-r3-1 の識別可能性だけ。タイミング指標の分母と、非介入系列の母数を同時に直すなら r4 は不要（delta 確認で足りる）。
