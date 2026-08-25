• ## Verdict

  **CUMULATIVE GO-with-concerns**（懸念2件はいずれも1行修正・決裁前に潰すこと）。A1〜A8 すべて、r2 裁定の採用リスト通りに v0.4 / v0.2 へ反映済みであることを確認した。

  | # | 要求 | 確認結果 |
  |---|---|---|
  | A1 | 誤発火=必要性の反実仮想・比の向き明記・harmless/harmful 層別 | **RESOLVED**。prereg §1: `fired ∧ 対照 bare に window_error 無し` のみを necessity-false-fire とし、`cost_ratio = tokens(sentinel) / geomean(tokens(bare 同一 model×task 全 seed))` で分子・分母を明記、<1.0=harmless / ≥1.0=harmful の層別。「発火+completed は定義に使わない」も明記。r2 の逆転構造（発火して5x燃焼が除外される）は排除された |
  | A2 | ライブ sweep 廃止・オフライン replay・両側化・codex 確認セル | **RESOLVED**。§2 較正節: {40k,80k,120k}×{40%,50%,60%} 全格子を bare/shadow 系列へ再適用、制約（codex/qwen 発火率0 ∧ harmful率 ≤10%）下で発火タイミング指標を最大化、採用値が既定と異なる場合のみ codex 確認セル1本（条件付き本数に正しく反映）。「非介入腕の系列に限り妥当」「較正≠効果推定」も明記 |
  | A3 | mid-task handoff 契約 | **RESOLVED**。§3: 発火ターン完走済み・fresh context で先頭から・depth 1・re-fire 禁止・workspace 残置・採点除外・**トークン集計凍結（parent_id で親+全子を機械合算）**。過大見積もり方向の安全性の注記も妥当 |
  | A4 | 橋渡し条項 | **RESOLVED**（ただし下記 NB-1 の§0/§4 不整合あり）。§0: 測るのは発火タイミングの質・nudge 効果への読み替え禁止・従属率は v1 運用ログで事後観測 |
  | A5 | slope 凍結 | **RESOLVED**。DESIGN §4: MA 比較が両レグ・min(T_abs, w×W) の実効挙動正文化・slope=(MA_t−MA_{t−K})/K, K=3・projection・M=10・未取得時=発火しない。縮退規則は NB-2 参照 |
  | A6 | 全腕 shadow・turn 系列必須保存 | **RESOLVED**。prereg §1 影評価（全腕 tap+判定、`nudge_disposition: shadow`）+ DESIGN §6 で turn 系列を ledger に毎ターン保存（要約のみ不可の理由付き） |
  | A7 | overflow 三分割・miss=window_error | **RESOLVED**。task_end の3フィールド分離 + prereg §1 の miss 定義は window_error キー・lead ≥1/≥3 の2本・runtime_compaction は記述報告（二面性の相互参照つき） |
  | A8 | 判定手続き凍結 | **RESOLVED**。§4: confirmatory/descriptive ラベル・統合規則1文凍結・ペア幾何平均/全ペア中央値・rule of three 併記・副腕2 は下限つき（+2/8 両モデル同方向）・副腕1 は件数ベース・p2-L 落としの読み替え条件（0.6→0.8）併記 |

  本数の検算: 48+4+8=60、確認セル条件付き+1 → 「60〜61+smoke 2」は v0.2 内部で整合。r2 裁定書の「62本」は裁定側の算術ミスで、v0.2 の方が正しい（60〜61）。48+4+8+1 の構成は依頼文とも一致。

  ## New blocking findings

  **なし。** ラチェット規則に照らし、改版で導入された実証可能な欠陥・未達のゲート基準は認めない。D1〜D5 および既裁定事項の再審は行わない。

  ## Non-blocking findings

  - **NB-1（決裁前に1行修正を推奨）: §0 と §4 の qwen 扱いの不整合。** §0 は「default-on 判定は…無発火保証（codex/qwen）にのみ依存する」と qwen を判定依存に含めるが、§4 の qwen 行は「外れたら prior 設計に差し戻し（GO 判定には中立）」、統合規則も codex のみを要件とする。整合的な読み方（無発火保証は replay 較正の制約で担保済み・ライブ qwen セルは較正妥当性の検証であり GO 入力ではない、かつ qwen 発火は harmful false-fire 条項がバックストップする）は存在するが、現状の本文は両義的。§0 を「codex 無発火」に修正するか、qwen の役割を「較正のライブ検証」と1文明記するか、どちらかに倒すべき。なおこの緊張は r2 裁定書の A4 と A8 の文言自体に由来し、writer は両方を忠実に写したもの——裁定側の対案提示が速い。
  - **NB-2（1語修正）: DESIGN §4 縮退規則の「傾きはターン2から」は K=3 と矛盾。** 述語ブロック（唯一の定義）では `t−K 未取得なら slope 未定義` なので slope が定義されるのは最速でターン4（MA_1 が存在する時点）。「傾きはターン4（=K+1）から」に直すこと。述語ブロックが正として優先されるため実害は無いが、凍結済み述語のすぐ隣の散文が矛盾しているのは実装者を迷わせる。
  - **NB-3（明記推奨・軽微）: replay 対象系列の打ち切り。** sentinel 腕の親系列は発火ターンで打ち切られるため、replay 閾値が本番採用値より緩い格子点では「発火したはずの時点」が観測されない（打ち切りバイアス）。制約チェック（codex/qwen 発火率0）は bare/shadow 系列で完結するので選定規則は壊れないが、sentinel 腕系列を replay 対象に含めるか否か（§3 の子タスク shadow 系列は非介入なので含めてよい）を1文で明確化すると実装時の解釈ブレが消える。「48本」の計数もこの整理次第で確定する。
  - **NB-4（軽微）: harmful 率 ≤10% の分母未指定。** necessity-false-fire 件数に対する割合か、全 replay run に対する割合か。格子選定の機械実行前に1語で固定すべき。

  ## Model identity

  kimi-k3（Kimi / Moonshot AI）— r1・r2 と同一正席。本 r3 は fresh context・同梱資料のみに基づく delta 審査。

