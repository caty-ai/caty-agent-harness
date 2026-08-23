# EV-008 LITE — sentinel の効果の手応え確認（探索・封印前）

2026-08-23 / 翔さん GO（最小構成・段階型に更新: 「まず本当に効くのか+何を持って育ったとするか→
最小1LLM→効果があれば他展開」）/ 位置づけ= **探索ラン**。本走の確証統計には算入しない。

## Phase 0（API コスト 0）: 既存 EV-006 transcript への述語 replay

EV-006 の bare 走行は per-turn usage を transcript に全記録済み。凍結述語（T_abs=40k/w=50%/N=3/K=3/M=10）
を後追い適用し、モデル毎に「injected がどう育つか・既定閾値はどのターンで発火するか・どの軸か」を出す。
- 答えが出る問い: **「文脈が育ってきた」は実データでどう見えるか / 既定 40k は過敏か妥当か /
  検索型（codex/qwen）は本当に発火しないか**（無発火保証の事前確認・タダ）
- ここで 40k が全モデル即発火なら、ライブに行く前に候補 {80k, 120k} の replay で当たりをつける
  （lite 内でライブの閾値はいじらない — replay は探索なので自由に振ってよい）

## Phase 0 結果（2026-08-23 実施・355 run 系列・results/ev008-lite-phase0-replay.tsv・API コスト0）

1. **T_abs=40k は既定として不成立が確定**: claude 系（sonnet/opus/haiku 帯の全 bare run）で
   **ターン1即発火**。Fable r2 の「レジーム差（per-step 注入 vs 累積プロンプト）」警告が実データで裏付け
   られた。40k のままライブに行くと sentinel ≒ 常時harness になり実験が無意味。
2. **80k が「タスク中盤で発火」の妥当帯**: p1-L 系（~110-128k 到達・45-55 turn）で t28-33 発火 =
   進行の約6割時点。120k は t40-47 = ほぼ終盤（手遅れ側）。
3. **検索型の無発火保証は 80k 以上で実データ成立**: qwen bare は max 76k で頭打ち（平坦な曲線）→
   80k/120k で **no-fire** ✓。「モデル由来の検索型は構造的に発火しない」が実測で確認済み。
4. **副産物: tap の盲点を2つ発見**（タダで）: ①glm/muse の shim 経由 bare は transcript の per-turn
   usage が全ゼロ（=現状 sentinel が盲目になる経路・tap 正規化の実装課題として #159 実装 Issue へ）
   ②pilot-sonnet5 の p2 系は 340-675k 到達 = [1m] 窓での走行と推定・ctx=200k 仮定の replay 値は
   その行だけ解釈注意。
5. **「文脈が育ってきた」の実像**: 全読み込み型は単調増加で 80k 跨ぎが明確・検索型は 70k 台で平坦。
   水位軸だけで両者は綺麗に分離する（slope 軸が効いたのは grok の急成長 run のみ）。

**Phase 0 判定: 述語の骨格は機能する。ライブ Phase 1 は T_abs=80k（探索値・記録済み変更）で実施。**

## Phase 1（最小ライブ・1 LLM）: sonnet-5 × p2-L × sentinel 腕 1本

1本で「本当に効くのか」の両面が見える: 発火タイミング（Phase 0 の予測と一致するか）+
発火→分解→完走でトークンが bare 比で減るか（対照= EV-006 実測値）+ handoff 契約の実効性。

## Phase 1 結果（2026-08-23 実施・results/ev008-lite-phase1/）

**成功。** sonnet-5 × p2-L-i1 × sentinel（T_abs=80k・w=50%・ctx=200k）:
- **発火= turn 15 / level 軸 / MA=86,110（abs 閾値）** — Phase 0 の replay 予測帯（t16〜44）とほぼ一致
- **outcome= decomposed → 20/20 正解**（window_error なし・compaction なし・511秒）
- **総トークン（親+子合算）= 4.92M** vs 対照:
  - bare 実測= 21.7M / 24.1M（**約4.4〜4.9x 節約**）
  - always-harness 実測= 3.53M / 5.44M（**同帯に着地** — 15ターン bare で様子を見たコスト込みでこの水準）
- 意味: **モデルを事前分類せずに、実測だけで harness 並みの経済性に到達**。sentinel の中核仮説が
  初のライブ1本で成立。
- 記録ノート: score.json の task_resolved=false は既知のフィールド癖（正答は correct_count が正）。

## Phase 2 結果（2026-08-23・haiku= results/ev008-lite-phase2-haiku/・qwen= …-qwen/）

- **haiku × p2-M**: 発火 turn 26（level・MA 80.9k）→ 分解 → **20/20 完走**（3.92M・614s）。
  EV-006 で bare 崩壊していた帯 = **完遂効果もライブ成立** ✓
- **qwen × p2-M（shim・窓 262,144 ロック）**: **136ターン発火ゼロ**（max injected 75.9k < 80k）→
  bare のまま **20/20 完走** ✓。tap_status=no-cache-accounting が設計どおり申告された（shim は
  cache 分計を返さない）。総トークン 4.56M は EV-006 bare 2.93M より大きいが no-fire なので
  監視オーバーヘッドではなく run 間分散（n=1・要注記）。codex のライブ確認は専用 tap 実装後の
  本走に委譲（qwen が検索型代表を代行）。

## LITE 最終判定（2026-08-23）

**3条件同時成立 = GO 寄りの最大値**: ①haiku 完遂 ②sonnet-L 4.4〜4.9x 節約 ③検索型 無発火。
機構チェックも全数 PASS（イベントスキーマ・発火予測の一致・handoff・親子トークン合算・再帰なし）。
→ フル本走（EV008-PREREG v0.2 封印・60〜61本）の判断材料は揃った。決裁= 翔さん。

## Phase 2（当初計画・記録用）: haiku（完遂効果）/ codex（無発火のライブ確認）/ qwen（任意）

## 走らせるもの一覧（Phase 1-2・sentinel 腕のみ・対照は EV-006 実測値を流用）

| # | モデル | 課題 | 見るもの | 対照（EV-006 実測） |
|---|---|---|---|---|
| L1 | haiku | p2-M-i1 | 完遂効果: 発火→分解で bare の崩壊を防げるか | bare 崩壊 / harness 完遂+30pt |
| L2 | sonnet-5 | p2-L（EV-006 sonnet L と同一課題） | 節約効果: 発火→分解で bare 比のトークン減 | bare ~112k/turn / harness 4〜6x 安 |
| L3 | codex (gpt-5.6-luna) | p2-M-i1 | **無発火**: 一度も fire しない + tap オーバーヘッド僅少 | bare 完走（発火0が合格） |
| L4(任意) | qwen3.8-max (shim・窓262144明示) | p2-M-i1 | 検索型挙動モデルでの無発火 | bare 2.93M |

seed=1（EV-006 参照値と同一課題・同一 seed = 比較可能性優先。この重複ゆえ本走の確証には使えない、を明記）。

## 判定（探索なので方向のみ）

- **GO 寄り**: L1 で完遂・L2 でトークン減・L3 で発火0、の3つが同時に観測される
- **設計差し戻し寄り**: L3 が発火する（prior なし述語の誤爆）/ L2 で発火が遅すぎて節約が出ない /
  L1 で発火→分解しても完遂しない（handoff 契約の実効性不足）
- 機構チェック（全 run）: turn 系列・fire/alert/task_end イベントが DESIGN §6 スキーマどおり記録されること

## 実装（リグレベルの実験特例・core 実装は本走 GO 後）

- 述語= DESIGN v0.4 §4 の凍結値そのまま（T_abs=40k / w=50% / N=3 / K=3 / M=10）
- sentinel 腕= bare セッションの stream-json を**ライブ監視**し、ターン完了毎に injected を計算 →
  fire したらセッションを打ち切り、**封緘計画を fresh context で先頭から** task-runner（run_harness 経路）で
  実行（prereg §3 handoff 契約: depth1・re-fire 禁止・成果物残置・トークンは親+子合算）
- 非発火なら bare のまま完走（= codex/qwen ではこうなるのが合格）
- 40k が過敏すぎる兆候（L2/L1 で開始直後に発火）が出たら、それ自体を「T_abs レジーム差（Fable r2）の
  実証」として記録し、replay 較正の優先度を上げる — lite の中で閾値をいじらない（探索でも規律は保つ）

## 費用概算

3〜4本・p2-M×2〜3 + p2-L×1 ≈ 25〜60M トークン級（EV-006 単価実測より）。
