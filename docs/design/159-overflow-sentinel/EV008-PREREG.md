# EV-008 事前登録ドラフト（翔さん決裁対象・#159 D5）

status: DRAFT **v0.3**（2026-08-23・Alpha・翔さん指示によるローリング化改版・3席 delta 未実施）

> **公開版注記（2026-08-25）**: 本文書は封緘前のローリングドラフト snapshot であり、実走を統治した
> 封緘版（`EV008-PREREG-DRAFT.md` SEALED v1.0 + モジュール封印台帳・私設リグ・非公開）とは別物。
> また公開にあたり、アカウント運用の識別子・残量実測・リセット日程は redacted した（方法論上の要点=
> 腕×アカウント交絡の遮断・クォータ余裕率 50% ルール・は保持）。redact 箇所は […] で示す。
リグ: EV-006 封緘 corpora 再利用（corpora/main は封緘継続・読み取りのみ）。
目的: overflow sentinel（DESIGN v0.4）の **default-on 可否**を、発火タイミングの質・誤発火・見逃し・
コストの実測で判定する。

## v0.3 改版理由（翔さん指示 2026-08-23）

1. **一括封印 → ローリング封印**: クォータ現実（実験用サブアカウント群の 7d 残量が逼迫・リセットは
   順次到来 […]）と「opus を先に走らせると1週間クォータを塞ぐ」リスクから、**モデル別直列・
   モデルごとにモジュール封印**へ構造変更。後からのモデル追加（gemini/grok 等）をモジュール追加封印として許容する。
2. **opus をグリッドに追加**（翔さんマスト= haiku/sonnet/opus）。実行順は最後尾。
3. **account 設計を凍結対象に追加**（run_meta に account・腕×アカウント交絡の遮断規則）。

## 0. 橋渡し条項 — この実験が v1 の何をライセンスするか（A4・Fable r2）

sentinel 腕は auto-enqueue ON（実験特例）で走るため、本実験が直接測るのは
**「発火タイミングの質」= 分解が有益な時点で発火しているか**であり、v1 出荷形態（nudge のみ）の
効果そのものではない。default-on 判定は発火タイミングの質と **codex 無発火保証**にのみ依存する
（§4 統合規則が正・kimi r3 NB-1: qwen のライブセルは replay 較正の妥当性検証であり GO 入力ではない —
qwen 発火時は prior 設計への差し戻し材料・GO 側は harmful false-fire 条項がバックストップ）。
nudge への従属率は v1 運用ログ（fire.nudge_disposition / task_end）で事後観測し、本実験の結果を
「nudge に効果がある」と読み替えることを禁じる。

## 0.5 ローリング封印の構造（v0.3 新設）

- **CORE**（本紙 §1・§2C・§3・§4・§5・§7）= 1回だけ封印。全モジュールに共通適用。
  封印後の変更は fail-stop → 裁定差し戻しのみ（勝手に緩めない）。
- **モジュール**（§6 の M1〜M7）= モデル単位。**そのモデルの最初の run 開始前に個別封印**
  （封印記録= §8 台帳に日時+当該モジュール節の SHA）。未封印モジュールの記述は予告であり拘束しない。
- **追加封印の規律**: 新モデルの追加はモジュール追加として行う。エンドポイント種別（confirmatory /
  descriptive）と §4 統合規則に影響しない追加= 裁定者確認のみ。統合規則に触る追加= 3席 delta 1周。
- **確証の読み方**: モデル間比較の確証統計は「当該2モジュールが両方封印済みで、かつ CORE が
  同一版」の場合のみ許す。それ以外は記述報告。**最終 default-on GO は M4(codex) 完了まで宣言しない**
  （§4 統合規則が codex 発火0 を必要条件とするため。qwen は代行にならない）。
- **直列順（予定・拘束は各モジュール封印時点）**: M1 haiku → M2 sonnet → M3 qwen（別クォータ系のため
  M1/M2 と並走可）→ M4 codex（tap 実装レーン完了後）→ M6/M7 gemini・grok（任意・tap 完了が条件）→
  M5 opus（最後尾・重量級）。

## 1. 凍結する定義

- **注入**: `injected = input + cache_read + cache_creation`（DESIGN §4 と同一・全腕同一計上）
- **影評価（shadow）**（A6・Opus r2 B2）: **全腕**で tap と sentinel 判定を常時実行し、bare /
  always-harness 腕では nudge を抑止（`nudge_disposition: shadow`）。per-turn `injected` 系列は
  全 run で ledger に保存（replay・miss 判定・事後再計算の唯一の材料）。
- **窓エラー / 圧縮の分離**（A7・Opus r2 B3）: `window_error`（API 拒否）と `runtime_compaction`
  （ランタイム申告）と `compaction_suspected`（ヒューリスティック）は別フィールド。
- **見逃し (miss)**: `window_error` が起きた run（bare/shadow 系列で判定）で、発生の lead ターン以上前に
  shadow 判定の fire が無かったもの。**lead ≥1 と ≥3 の2本で報告**（GLM r2）。runtime_compaction は
  miss の主定義に使わず、回数・タイミングを記述報告（設計側の「自衛」解釈との二面性は本節が正・
  相互参照= DESIGN §4）。
- **誤発火 (false fire)**（A1・比の向きを凍結）: `fired ∧ 対照 bare に window_error 無し` を
  **necessity-false-fire** として数える（必要性の反実仮想のみ）。その上で
  `cost_ratio = tokens(sentinel腕 run) / geomean(tokens(bare 同一 model×task 全 seed))` を計算し、
  cost_ratio < 1.0 = **harmless**（発火は不要だったが安く済んだ）/ ≥ 1.0 = **harmful**（発火が
  コストを悪化させた）に層別して両方の率を報告する。「発火+completed」は定義に使わない。
- **正答**: EV-006 と同一の第2エンドポイント（正答+引用突合）。read-coverage ゲートは合否に使わない。
- **発火率の解析単位はターン**（Opus r2 NB4）: 分母= 当該腕の総ターン数（run_meta と turn 系列から機械集計）。
  発火0 の報告には rule of three の 95% 上限（≈3/総ターン）を併記する。

## 2C. CORE — 腕構造・閾値・較正（v0.3 で §2 を再編）

### 腕（全モジュール共通）

bare(shadow) / always-harness(shadow) / sentinel（auto-enqueue ON・実験特例・§3 handoff 契約）。
モジュール標準グリッド= **3腕 × 2課題（p2-M-i1 / p2-L 帯1本・課題 ID はモジュール封印時に固定追記）×
2seed = 12本/モデル**。副腕はモジュール節に個別定義。

### 閾値の凍結（v0.3 変更・旧 Phase1→replay→Phase2 の置換）

- **(T_abs, w) = (80k, 50%) を CORE 封印時にロック**する。根拠= LITE Phase 0 replay
  （EV-006 実 transcript 355 run 系列・API 0・`results/ev008-lite-phase0-replay.tsv`）:
  40k= claude 系ターン1即発火で不成立 / 80k= 進行約6割時点の発火帯 / 120k= 終盤で手遅れ側 /
  qwen は 80k 以上で no-fire 成立。N=3 / K=3 / M=10 は DESIGN v0.4 §4 のまま。
- 旧 v0.2 の「Phase 1 全モデル32本 → replay 較正 → ロック」は、モデル直列化により**事後検証 replay**
  に置換する（grok r3 NB3 の意図= 「sentinel 測定は出荷既定と同一設定で行う」は、全 run を封印済み
  (80k,50%) で走らせることでより強く保たれる。**全実行を通じて閾値変更は一切行わない**）。
- **事後検証 replay（各モジュール完了時+全体完了時）**: 蓄積した非介入 shadow 系列
  （bare/always-harness）へ (T_abs, w) ∈ {40k, 80k, 120k} × {40%, 50%, 60%} を全格子再適用。
  制約= ①codex・qwen の replay 発火率 0 ②necessity-false-fire 率 ≤ 10%（分子= fire したが同
  model×task の bare 全 seed が window_error 無し〔all-seed clean の strict 読み・glm r3 NB1〕だった
  run 数 / 分母= 当該格子点の replay 対象 run 総数）。**(80k,50%) が実行可能集合から外れたら fail-stop
  → 裁定差し戻し**（以後のモジュール開始を停止。完了済みモジュールの結果には「較正逸脱」を注記）。
  harmful/harmless のコスト層別はライブ本走の A1 分析でのみ報告（replay では計算不能）。
  replay 対象= 非介入2腕の系列のみ。sentinel 親系列は打ち切りバイアスのため対象外（kimi r3 NB-3）。
- 較正≠効果推定（Opus r2 NB6）: (80k,50%) は LITE 探索由来の較正値であり、効果推定は本走
  エンドポイントで行う、と報告書に明記する。

### モジュール内の実行順（旧 Phase 構造のモジュール内版）

各モジュールで **Phase A= 非介入2腕（bare/always-harness・shadow）→ Phase B= sentinel 腕**。
Phase A 完了時に当該モデルの事後検証 replay を1回実施（上記制約チェック）→ PASS で Phase B へ。
課題×腕の実行順は Phase 内シャッフル（orchestrate.py shuffle-seed 記録）。

## 3. sentinel 腕の mid-task handoff 契約（A3・実験特例の再現性）

- fire はターン完了後に判定される → 発火ターン自体は完走済み
- auto-enqueue は**封緘済み計画を fresh context で先頭から**実行（部分再開はしない — v1 に文脈蒸留機構が
  無いため。この保守的選択は sentinel 腕のコストを過大側に見積もる= 承認に不利な方向で安全）
- depth 1・re-fire 禁止（分解後の子タスクで sentinel は shadow のみ）
- workspace 成果物は残置（後続 step が上書き可）・発火前の途中成果物は採点対象に含めない
- **トークン集計の凍結**（codex r2）: sentinel 腕の total_tokens = 親タスク（発火まで）+ 分解後の
  全子タスクの合算。task_id の親子リンク（parent_id）で機械集計する

## 4. モデル別エンドポイント（confirmatory / descriptive を凍結・A8）

| モデル | エンドポイント | 種別 | 判定 |
|---|---|---|---|
| codex | per-turn 発火率（分母=総ターン） | **confirmatory** | 発火 0（rule of three 上限併記）・トークン比ペア幾何平均 ≤ 1.05 |
| qwen | per-turn 発火率 | **confirmatory** | 発火 0 予測。外れたら prior 設計に差し戻し（GO 判定には中立） |
| sonnet | トークン比（sentinel/bare・ペア幾何平均・全ペア中央値） | **confirmatory** | 中央値 < 1.0（L帯があるとき < 0.8 を努力目標として併記） |
| haiku | 完遂率・正答 | **descriptive** | n=4 の粒度（25pt 刻み）ではマージン判定不能のため記述報告（方向の一貫性のみ見る） |
| opus（v0.3 追加） | トークン比+完遂率 | **descriptive** | n=4 につき記述報告。sonnet 確証と同方向かの一貫性のみ見る（GO を覆さない） |
| gemini / grok（候補） | 発火タイミング・トークン比 | **descriptive** | モジュール封印時に固定（統合規則に入れない） |
| 副腕1 | miss（lead≥1 / ≥3） | **confirmatory**（件数ベース） | miss 0/観測数を報告（率ではなく件数と分母を明記・n=2 の点推定と明記） |

**統合規則（1文で凍結・v0.2 から不変）**: default-on GO の必要条件= 「codex 発火率 0」∧「codex トークン比
ペア幾何平均 ≤ 1.05（違反= tap オーバーヘッド疑いとして差し戻し・glm r3 NB4）」∧「sonnet トークン比
全ペア中央値 < 1.0」∧「harmful false-fire が全ペアで一貫して発生しない」。haiku・opus・副腕2・
候補モジュールは GO を覆さない（明白な悪化が全ペア一貫の場合のみ差し戻し）。

## 5. 環境凍結・実行規律

- qwen shim: `CLAUDE_CODE_MAX_CONTEXT_TOKENS=262144` / 全 shim: unset CLAUDE_BIN 版+wrapper ガード有効
- TR_STEP_TIMEOUT_S は EV-006 と同値。腕間でモデル版・effort・timeout・env 固定
- 各 run に wall-clock・モデル版・run_meta（arm/seed/shuffle_seed/T_abs/w/N/M/K/**account**）をスタンプ
  （Opus r2 NB7: 時間トレンドの記述チェックを解析に含める。v0.3: account フィールド追加）
- DLQ（インフラ起因）は同 seed 1回だけ再走・`rerun: true` フラグ付与・再走除外の感度分析を1行報告
  （Opus r2 NB8）。2回目 DLQ は欠測として報告。**クォータ起因（429/limit）の中断も DLQ 扱い**で
  同規則（翌スロットの同一アカウントで再走= 腕×アカウント遮断を保つ）

### アカウント設計（v0.3 新設・凍結）

- 対象= 実験専用サブアカウント6垢のみ（本垢は実験に不使用 […]）。
  qwen/codex/gemini/grok は別クォータ系のため本節の対象外。
- **腕×アカウント交絡の遮断**: 同一モデル内の 1セル（task×seed）の3腕（bare/always/sentinel）は
  **必ず同一アカウント**で走らせる。標準グリッド12本= 4セル → 4アカウントに1セルずつ割当、
  残り2垢= DLQ 再走・副腕用の予備。セル→アカウントの割当はモジュール封印時に固定追記。
- 割当の実測記録: 起動時の swap ツールの active アカウントを run_meta.account に記録し、事後に
  照合可能にする（宣言と実測の不一致= DLQ 扱いで同一垢再走）。
- **クォータ余裕率 50%**: 各スロット開始時に当該垢の 7d 残量を確認し、
  「そのスロットで使う見込み量 × 2」が残っていなければ開始しない（翌スロットへ繰り越し）。
  429/limit 検知= スロット即中断 → DLQ 規則で翌スロット繰り越し。

### 時間割（叩き台・拘束はモジュール封印時）

- 1日= 2〜3スロット（アカウントのクォータ窓リセットに合わせる）× 3〜7日。時間帯運用はアルファ一任（翔さん 2026-08-23）。
- M1 haiku= 8/23 夜〜（軽量・現行残量内で可の見込み）→ M2 sonnet= 7d クォータ窓の到来順に投入 […] →
  M3 qwen= 並走 → M4 codex= tap レーン完了後 → M5 opus= 最後尾（全モジュール完了後の空き週間帯）。

## 6. モジュール登録簿（各モジュール封印時に課題 ID・セル→アカウント割当を追記して封印）

### M1: haiku（descriptive・完遂効果）
標準12本 + 副腕2 haiku 側（{B: 本人分解, C: 強モデル分解} × p2-M × 2seed・always-harness 固定= 4本）
= **16本**。記述統計のみ（A8: n=4/セルは確証に足りない）。副腕2 の読み替え規則は v0.2 のまま:
v2 ナッジ宛先変更を採るのは「完遂率差 C−B ≥ +2/8 が haiku/sonnet 両モデルで同方向」の場合に限る。

### M2: sonnet-5（confirmatory・トークン比）
標準12本 + 副腕1（強制オーバーフロー: sentinel / bare(shadow) × p2-L × 2seed・`ctx_window=64k`
上書き・bare の window_error 到達を事前 smoke 2本で確認= 4本+smoke2）+ 副腕2 sonnet 側 4本
= **20本+smoke2**。64k 帯では相対項 w が実効閾値になる（DESIGN §4 min() 挙動）= 相対項の生きた検証を兼ねる。

### M3: qwen3.8-max on claude CLI shim（confirmatory・無発火）
標準12本 = **12本**。`--claude-bin runner/qwen_bin_shim.sh --ctx 262144`。別クォータ系につき
M1/M2 と並走可（腕×アカウント遮断は claude 垢に対する規則のため非適用・shim 側は単一系で固定）。

### M4: codex = gpt-5.6-luna（confirmatory・無発火+トークン比 ≤1.05・**最終 GO の必須モジュール**）
標準12本 + 確認セル1本 = **13本**。前提= codex 用 tap 実装レーンの完了と smoke PASS
（実装レーンは本 prereg の外・完了時にモジュール封印）。

### M5: opus（descriptive・v0.3 追加・**最後尾固定**）
標準12本 = **12本**。重量級（sonnet L 帯単価 10〜30M/本の上位互換を想定）につき、
全モジュール完了後・週間クォータの空き帯で実行。モジュール封印時に p2-L 帯を落として
6本（M帯のみ）へ縮退する選択肢を残す（縮退時は L 帯読み替え撤回を注記・glm r3 NB5 と同型）。

### M6/M7: gemini(agy) / grok（候補・未拘束）
tap 実装レーン完了が条件。エンドポイントは descriptive 固定（統合規則に入れない）。
封印時に本数・課題を確定。実施しなくても最終 GO 判定に影響しない。

**総本数（M1〜M5 確定分）: 16 + 20 + 12 + 13 + 12 = 73本 + smoke2**（M5 縮退時 67本+smoke2）。
概算 380〜480M トークン級（M5 縮退時 330〜420M）。削減優先順: ①M5 の L 帯縮退 ②副腕2 ③M3。
副腕1（miss）と shadow 評価は削らない。

## 7. 解析・報告の凍結（v0.2 から継承）

- 集計の正= 各 results dir の score.json（task_resolved は癖フィールド・**correct_count が正**）
  + sentinel-events.jsonl。replay= `runner/sentinel_replay.py`。
- モジュール完了ごとに中間報告（記述）。確証判定の宣言は該当モジュールの封印条件を満たす時のみ。
- 発火0 報告には rule of three 上限併記。時間トレンド記述チェック（NB7）・DLQ 感度分析（NB8）を含める。

## 8. 封印台帳（CORE / モジュールごとに追記）

| 対象 | 封印日時 | SHA-256（対象節の連結） | 裁定 |
|---|---|---|---|
| CORE（§1,2C,3,4,5,7） | — | — | 3席 delta 待ち |
| M1 haiku | — | — | — |
| M2 sonnet | — | — | — |
| M3 qwen | — | — | — |
| M4 codex | — | — | — |
| M5 opus | — | — | — |

## 9. 未決（翔さん決裁で埋める欄）

1. v0.3 ローリング構造の GO（3席 delta 後）
2. p2-L 帯の課題選定（EV-006 既存 L 課題の流用 or 新規生成）— M1 封印時に固定
3. P1 本走との実行順序・予算配分
4. M5 opus の縮退（12本 or 6本）— M5 封印時でよい
