# DESIGN: #159 overflow sentinel — 文脈圧力の実測で task-runner を発火する

status: **v0.5**（2026-08-25・Alpha・L1-9 r3 PASS〔3席 CUMULATIVE GO 収束・blocking 残0〕+
**EV-008 完了・default-on GO 宣言済み（案A・2026-08-25）を「設計の現在地」として反映**・サイズ H）
inputs: PILOT.md（訂正節含む）/ REPORT-runtime-context-survey.md / REPORT-pattern4-rootcause.md /
REPORT-hermes-provider-layer.md / REPORT-hermes-provider-deep-research.md / REPORT-qwen38-artifacts.md /
#159 clarify 決裁5点 / L1-9 r1〜r3 裁定（reviews/ADJUDICATION-r1〜r3-FINAL.md）/
セロ一次証言（family-vault 20_projects/family-os-external-proof/cero-hearing-task-runner-20260823.md）/
**EV-008 確定報告（experiments/ev006/EV008-FINAL-REPORT.md・数字の正= step5-reconcile.py 出力）+
GO 宣言（EV008-GO-DECLARATION.md・翔さん決裁）**
関連: harness#162（zero-output attempt の事後分類・早期 DLQ）/ EV-008 事前登録= 別紙 `EV008-PREREG.md` /
公開反映済み= PR #176（README `#model-effects` / docs/benchmark.md `#ev-008`・v0.14.1）

## 0. 設計の現在地 — EV-008 完了・default-on GO 宣言済み（2026-08-25）

本設計の検証実験 EV-008 は完了し、**default-on GO が宣言された**（案A・翔さん決裁 2026-08-25・
正本= EV008-GO-DECLARATION.md）。GO 4条件と結果:

| 条件 | 結果 | 証拠 |
|---|---|---|
| ① codex 発火率 0 | **0/127 turns**（rule of three 95%上限 2.4%/turn） | M4 0/38 + 診断 0/45 + M4' 0/44 |
| ② codex トークン比 GM ≤ 1.05 | **0.9944** | M4' n=3 反復平均（3席 delta 経由封印） |
| ③ sonnet 全ペア中央値 < 1.0 | **0.801** | M2 標準12本 |
| ④ harmful false-fire 全ペア一貫なし | **1/4 ペアのみ** | M2 §1 A1 層別 |

**必須併記3点（GO 宣言と不可分・省略禁止）**:
1. **M4 の歴史**: codex 比条件は M4（n=1）で GM **1.337 FAIL** となり条文どおり差し戻された。
   ②は「M4 n=1 FAIL（歴史）∧ M4'（n=3 反復平均・data-informed 事後設計・3席 delta レビュー経由で
   封印）で成立（現行）」であり、M4 FAIL の抹消ではない。
2. **努力目標未達**: sonnet 中央値の努力目標 <0.8 に対し **0.801 で僅差未達**（判定閾値 <1.0 は成立）。
3. **残余不確実性**: 標準セルのペア比は n=1/ペア（M4' M帯のみ n=3）。M帯の走行間 SD≈平均の30〜40%・
   n=3 でも比 SE≈25%級 = 0.9944 は「閾値の内側」であり「明確に下回る」ではない。

**モデル別実測サマリ**（全数字= EV008-FINAL-REPORT.md / step5-reconcile.py 突合済み・実験パラメータは
全期間 T_abs=80k / w=50%）:
- **全読み込み型= 主戦場**: haiku 中央値 0.35（descriptive・4/4 発火）/ sonnet 中央値 **0.801**
  （4/4 発火→分解→child 完走・正答維持・L-i2 は 0.286=71%減）/ opus 中央値 **0.923**（post-GO 監視
  PASS・4/4 発火→分解→完走・全ペアで sentinel が安い側）
- **検索型= 無発火が仕様**: codex 累計 **0/127 turns**・GM 0.9944 / qwen sentinel 4/4 **無発火**
  （max injected 68,805–79,696 @80k・M-i2 は閾値まで304トークン→「観測範囲で無発火」に留める・
  0発火/約770ターン= 95%上限 ≈0.4%/turn）
- **第3類型（grok・descriptive）**: 発火型だが経済メリットなし — 4/4 発火→分解→完走（機構の頑健性を
  別ランタイムで実証）する一方、bare が極めて安く（763k〜2.4M）ペア比中央値 **2.145 >1.0**。
  「**成長型×低 bare 単価= default-on 不向き**」。
- 副腕1（64k 強制オーバーフロー・プロキシレーン）= **継続中**（GO 4条件の対象外・完了時は追補扱い）。

**EV-008 結果から昇格する設計制約（v1 実装に対して規範）**:
- **C-1 per-model 適用判定**: default-on の適用範囲はモデル別経済プロファイルで決める。発火・分解・
  正答維持が正しく動くこと（grok で実証済み）は導入判断と独立 — 判断は **bare 対比の経済**で行う。
  grok 型（成長型×低 bare 単価）には default-on を適用しない。
- **C-2 blind-path ガード**: per-turn usage の実値が得られない経路では sentinel を有効化しない。
  実測の盲目経路= glm/muse（shim 経由で per-turn usage 全ゼロ）・kimi（usage 非放出）。全ゼロ usage の
  検出時は起動拒否（または明示的 disabled 記録）とし、§3 の `tap_status: absent` と同様に
  「発火しなかった」と「見えていなかった」を区別可能な形でログに残す。
- **C-3 ホスト圧縮との同居**: 水位管理者は同時に1人（独自コンパクションを持つホストでは
  ①ホスト圧縮先行→sentinel 恒久不発火の飾り化 ②二重介入、の両リスク）。検知土台は既存
  （task_end の runtime_compaction / compaction_suspected・本走全走行で false 実測）。実装形
  （switcher config）の包含は実装 Issue の clarify で確定。

GO 宣言の射程= claude 系ランタイム + codex は「無発火・課金非上乗せ」の安全条件で同居可。
出荷順序（opt-in 先行か default-on 即時か）は GO 宣言（機構の可否）と別判断で、実装 Issue 側で決める。

## 1. Why — なぜ作るのか・作らないと何が起きるか

**解いている問題**: harness（task-runner）の価値の実体は「実行を最後まで持続させる規律」であり、
その規律には毎ターンの実コスト（STATE 注入・rubric・checkpoint・verifier）がかかる。EV-006 で
「効く場面」と「害になる場面」の両方が実数で確定した — haiku は完遂率 +30pt（規律が完遂そのものを
可能にする）、重量級全読み込み型は最大 6x のトークン節約、逆に codex 系検索型は 4〜6x の純損。
つまり**常時ONは正解ではない。問題は「いつ規律のコストを払うべきか」を判断する装置が存在しないこと**
（現状の発動条件は「人間か orchestrator が tr-enqueue した時」のみ）。

**なぜ「実測発火」か（静的分類ではなく）**: ①同族内で割れる（sonnet=選択読み / opus=網羅読み）
②ランタイムで決まらない（Qwen3.8 は claude CLI 上でも訓練由来で検索型に振る舞う=REPORT-qwen38）
③新モデルが出るたび分類表の保守が要る。3点とも実測済みの根拠がある。

**作らないと何が起きるか**: 弱いモデルは黙って未完のまま終わり、強いモデルは黙って数倍のコストを
燃やす。どちらも「静かに」起きる — CLAUDE_BIN 事故（600〜1200s 無音）と同型で、観測装備が無ければ
気づけない。sentinel は判断装置であると同時に、この観測装備（per-turn 注入・TTFB）を常設する。

**なぜ今か**: セロの一次証言で裏が取れた — 効いたのは「実行規律と証拠つき完了判定」で、常時ONの
過剰さは導入2日目に露見済み（2026-07-04 `casual conversation is not a task` 除外修正 d22ad96）。
runtime 調査で OpenClaw/Hermes とも「圧縮はあるが文脈圧力→分解の自動経路は無い」= オリジナル寄与。

## 2. 問題の構造（EV-006 の教訓 + 系譜の訂正）

EV-006 確定の3パターン（第4パターンは配線バグで撤回・訂正節参照）:
①弱い全読み込み型= 完遂を可能にする ②強い全読み込み型= 同精度で 1.3〜6x 節約 ③検索型= 純損。

系譜の訂正（セロ証言）: 「Cero adapter」= モデル内の完遂規律+独立検証（bootstrap block 方式）と、
「task-runner」= モデル外から fresh context で各 step を再駆動する driver（設計 Alpha・Luca 向け）は
**別物**。sentinel が発火して呼ぶのは後者。前者の規律効果（迷子防止・証拠つき完了）は
発火時ナッジの中身（§6）に軽量な形で輸入する。

## 3. 配置: core 判断ループ + ランタイム別 usage tap（D1=B）

```
[runtime adapter]                [core: sentinel]                  [core: task-runner]
 turn / byte tap  ──events──▶  水位+傾き+step健全性 判定  ──fire──▶  v1: nudge+ログ
 (claude/codex/agy/…)                                              v2: auto tr-enqueue (flag)
```

**tap 契約 v1**（この節が正・F1/F6 反映）:
- `turn` イベント（ターン完了時に1発）:
  `{schema_version, ts, task_id, turn_idx, input_tokens, cache_read_tokens, cache_creation_tokens,
   output_tokens, model, ctx_window_claimed?, tap_status}`
  - **意味論を固定**: `input_tokens` は cache_* を含まない正味（排他加算）。OpenAI 系のように
    `prompt_tokens` が cached を内包するランタイムは、アダプタが正規化してから送る（二重計上禁止）。
  - `cache_creation_tokens` を報告できないランタイムは 0 を送り、`tap_status: no-cache-accounting`
    を申告する（水位が系統的過小になることを core が知っている状態にする）。
  - `ctx_window_claimed` はアダプタの申告値（optional）。採用判定は core の梯子（§5）が行い、
    どの段が勝ったかをログに残す。
- `byte` イベント: `{ts_request_sent, ts_first_byte?}`（step 健全性軸用。**SSE ping や keep-alive は
  first byte に数えない** — Hermes の教訓の契約化）。
- 未知フィールドは無視（前方互換）。tap の無いランタイムでは sentinel 無効（現状維持）。ただし
  非発火サマリに `tap_status: absent` を記録し、「発火しなかった」と「見えていなかった」を区別する。

## 4. 発火規則（v1 で凍結する一意の述語・F1/F2）

**観測量**: `injected_t = input_tokens + cache_read_tokens + cache_creation_tokens`（turn イベント由来・実測のみ）。

**述語（これが唯一の定義・全変数を凍結）**:

```
MA_t        = mean(injected_{t-N+1..t}), N=3（取得済みが N 未満なら有る分の平均）
level_fire  = MA_t > min(T_abs, w × ctx_window)            # 比較対象は常に MA（injected_last ではない）
slope       = (MA_t − MA_{t−K}) / K,  K=3（MA 列上の差分。t−K 未取得なら slope 未定義=発火しない）
projection  = (ctx_window − MA_t) / slope   （slope > 0 のときのみ定義）
slope_fire  = projection ≤ M=10
fire        = level_fire OR slope_fire      （axis = level / slope / both を記録・§6）
alert       = ts_first_byte 不在のまま TTFB 床超過（fire とは別イベント・§4-1。fire 統計を汚染しない）
```

**OR の実効挙動を明記**（Opus NB1）: 実効水位閾値は `min(T_abs, w×ctx_window)` であり、
**ctx_window ≥ T_abs/w（既定なら 80k）のモデルでは絶対項が常に先に効く**。相対項が主役になるのは
小窓モデル（64k 級・EV-008 の人工縮小腕を含む）のみ。「相対=あふれ射影用」という v0.3 の説明は不正確
だったため削除。

- **縮退規則**: ターン1= injected_1 単独を MA とみなす（N 未充足時は取得済み分の平均）。
  傾きは**ターン4（=K+1）から**（述語ブロックの `t−K 未取得なら slope 未定義` が正・kimi r3 NB-2）。
- **絶対閾値 T_abs の由来**: EV-006 で harness が注入を抑えた上界 20〜40k/turn の上端。
  1M 窓モデルで「浪費帯 112k/turn が窓比 11% で永遠に発火しない」盲点を塞ぐ（F2）。
- **auto-compaction を観測したら**（注入の急落で検出 or ランタイムイベント）: MA と傾きをリセットし、
  保留中のナッジは取り下げる（ランタイムが自衛した直後に分解を勧めない）。圧縮検出は v1 では
  ヒューリスティック（前ターン比 40% 超の急落）でよい — 誤検出のコストはナッジ1回の抑制のみ。
- **モデル class prior は v1 では使わない**（unknown 一択・実測のみ。search prior の「実質オフ」は
  Qwen の runtime≠挙動問題で誤爆するため v2 の明示オプトインへ・F6）。
- **送信直前チェックポイントは v2**: 取得元（claude stream-json / codex turn.completed / agy result）は
  すべてターン完了後で、Hermes 位置（送信前ペイロード推定）の観測は現 tap では物理的に不可能（Grok r1#1）。
  1ターン遅れは EV-006 のスケール（数十〜200ターン）で無視できる。v2 で optional `pre_send` イベントを
  定義してから昇格する。

### 4-1. step 健全性軸（TTFB）— v1 は alert-only（F4）

- ゼロバイトのまま `TTFB 床`（90s・>50k tok 150s・>100k tok 240s・reasoning 系はモデル別 floor 表）を
  超えたら **検出+ログ+アラートのみ**。kill しない・step timeout は現行のまま（D3「提案のみ」と整合）。
- floor 表に無いモデルは **unknown= 最長床(240s)を適用**（GLM 欠載で誤殺した Hermes の前例の逆を張る:
  未知は殺さない側に倒す）。
- 所有境界: **sentinel 軸= 生きている間の検出+alert / harness#162= 死んだ後の attempt 分類+早期 DLQ**。
  共有するのは byte tap のみ。kill/再接続の semantics は v2 で #162 側と合同設計。

## 5. 閾値と ctx_window（D4: 実測由来の既定 + config 上書き）

| パラメータ | 既定 | 由来 |
|---|---|---|
| N（移動平均窓） | 3 turns | pilot の bare 立ち上がり 2〜4 turn |
| T_abs（絶対水位） | 40,000 tok/turn（較正候補 {40k, 80k, 120k}。**EV-008 実走は 80k/50% を全期間使用し GO 成立（§0）— 製品既定の最終確定は実装 Issue の clarify で行う**） | EV-006 harness 上界の上端（F2）。**系譜注記（Fable r2）**: EV-006 の 20〜40k は harness の per-step fresh-context 注入量・sentinel の injected は累積プロンプト全体でレジームが異なる。40k は過敏側（200k 窓の実質全タスクが中盤で跨ぐ）の可能性があり、既定の最終確定は較正に委ねる |
| w（窓比水位） | 50% | bare sonnet L帯 定常 ~56% の近傍。**導出ではなく同域の初期値** — EV-008 sweep で確定（Kimi r1 指摘の言い直し） |
| M（射影ホライズン） | 10 turns | 保守的（v1 の誤発火コスト= ログ1行+ナッジ1回） |
| TTFB 床 | 90/150/240s + reasoning floor 表 + unknown=240s | Hermes 実装値 + hermes#89241 の逆張り |

**ctx_window の4段梯子**: config 明示上書き > HF config.json（公開モデル・**訓練上限≠提供窓に注意**、
過大方向は T_abs 併置で無害化） > モデルカタログ > 保守既定 200k。採用段を `ctx_window_source` として
ログに記録。128k 実窓モデルに 200k 既定が当たる過大方向の見逃しも T_abs が受ける。

## 6. 発火時の動作（D3: v1 は提案のみ + 発火実測ログ）

**ナッジの中身（セロの段階介入モデルを輸入）**: 発火時にランタイムへ返す1メッセージは
「task-runner に分解しろ」ではなく、まず **delta 固定**を課す —
`Goal / 現在のステップ / 完了済みの証拠 / blocker / stop rule` の5点だけを書き出させ、
その上で「文脈圧力が閾値超過（実測値併記）。task-runner 分解を推奨」と続ける。
フル分解への昇格（auto-enqueue）は v2 フラグ裏。

**発火実測ログ（F5 + r2: fire / alert / task_end の3イベント分離 + turn 系列の常時保存・in-place 追記禁止）**:

```
turn:     （§3 の tap イベントをそのまま ledger に毎ターン保存。replay・miss 判定・事後再計算の材料。
           Opus r2 B2: 要約だけでは「あふれ何ターン前に閾値を跨いだか」を復元できない）
fire:     {ts, started_at, task_id, turn_idx, axis: level|slope|both, injected_ma, injected_last,
           value_kind: measured|estimated, threshold_hit: abs|ratio|both, ctx_window, ctx_window_source,
           slope, projection_turns, decision: nudge, nudge_disposition: shown|suppressed|shadow,
           model, runtime, tap_status, run_meta: {arm?, seed?, shuffle_seed?, T_abs, w, N, M, K},
           schema_version}
alert:    {ts, task_id, turn_idx, ttfb_ms, floor_applied, model, runtime, schema_version}
           （TTFB は fire と別イベント。Grok r2#5: codex の「発火0」合格判定を alert が汚染しないため）
task_end: {ts, started_at, task_id, outcome: completed|overflowed|decomposed|aborted,
           window_error: bool, runtime_compaction: bool, compaction_suspected: bool
           （Opus r2 B3: API 拒否とランタイム自衛を混同しない・ヒューリスティック検出は別フィールド）,
           total_tokens, injected_summary: {max, last3_mean}, fired_turns: [..], alert_turns: [..],
           nudge_disposition_final, tap_status, run_meta, elapsed_s, schema_version}
```

**ナッジのヒステリシス（Fable r2）**: nudge はタスクごと・軸ごとに1回。再提示は MA が前回発火時から
さらに `+10% × ctx_window` 上がった時のみ（連打による無視学習とログ肥大の防止）。

- **誤発火の定義はコストで行う**: 発火+completed は誤発火ではない（EV-006 の本命ケースは
  「完走するが4〜6x高い」）。判定は task_end の total_tokens と EV-008 の対照腕（別紙）で行う。
- 非発火タスクも task_end を1行残す（見逃し検証の対照・tap_status 込み）。
- 置き場: **task-runner ledger への合流を第一候補**（task_id で followup 結合が壊れない・Grok r1）。
  独立ファイルにする場合は「ledger 実装前に sentinel を単体計測するため」という理由を実装 Issue に明記。
- attempt receipt にも `first_byte_at`（null 可）を必須化（CLAUDE_BIN 事故で最も欠けていた1フィールド。
  #162 のスキーマと語彙を揃える）。

## 7. EV-008（D5）— 事前登録は別紙・**実施済み（結果は §0）**

事前登録の正本= `EV008-PREREG.md`（v0.2・翔さん決裁済み・実走完了 2026-08-25。結果と GO 宣言は §0、
確定数字は experiments/ev006/EV008-FINAL-REPORT.md が正）。設計時の骨子（記録として保持）:
主比較は**同一の封緘済み計画**を bare / always-harness / sentinel の3腕に渡して実行持続効果を分離
（セロ提案と一致）。分解者 B/C（本人分解/強モデル分解）は入れ子の別セル。強制オーバーフロー副腕
（窓 64k 人工縮小）で見逃し率を実測。codex 腕は「発火率0」自体が合格条件。qwen on claude CLI を
一般化腕に1本。w と T_abs の sweep。窓ロック等の env 凍結。

## 8. v2 ロードマップ（v1 非目標だが設計上の座席は確保）

- 送信直前チェックポイント（optional `pre_send` tap イベント）
- auto-enqueue（フラグ裏・**mid-task handoff 契約**= 現行 step の中断・成果物の引き継ぎ・
  新 task file への文脈蒸留、を定義してから）
- セロ提案の非文脈系発火軸: 同一失敗の2回以上反復 / tool call 増加なのに artifact・evidence 停滞 /
  未検証の副作用残留 / 証拠なき完了宣言。= 「liveness と evidence の番人」への拡張
- search prior の明示オプトイン / TTFB kill+再接続（#162 と合同設計・floor 表完備が前提条件）

## 9. 非目標（v1）

- 検索型ランタイムへの harness 強制 / 静的モデル分類表の保守 / 圧縮（compaction）との統合 /
  casual conversation・1〜2 tool call で閉じる作業への発火（セロ証言 d22ad96 の教訓を仕様化:
  sentinel は task-runner 管理下タスクと、tap を実装した長時間セッションのみを対象とする）

## 9-1. 実装 Issue の Done when へ送る検査項目（r2 で確定）

- tap 適合 golden-file テスト（アダプタ毎: 排他加算・cached 内包の除去・SSE ping 除外を固定入力で検証。
  Fable r2: 契約は「書けば守られる」側に倒れやすい — 違反は水位の系統誤差として静かに入るため）
- reasoning floor 表の実体収載（v1 表= 90/150/240s + 記名 override。無記名モデル= reasoning 含め 240s）
- TTFB 床の tier キー= 前ターンの injected（byte イベントに optional `request_size_estimate` を追加可）

## 10. レビュー履歴

- r1（2026-08-23・kimi-k3/grok-4.6/glm-5.3・GWC/NO-GO/NO-GO）: F1 述語一意化→§4 /
  F2 絶対閾値併置→§4-§5 / F3 EV-008 凍結→別紙 / F4 TTFB alert-only→§4-1 /
  F5 ログ分離→§6 / F6 細部→§3-§5。裁定= reviews-159-L19/ADJUDICATION-r1.md
- v0.3 追加入力: セロ一次証言（Why 節・ナッジ中身・v2 軸・非目標）・翔さん指示「Why を入れる」
- r2（2026-08-23・正席3= NO-GO/GWC/NO-GO + 参考3= codex/fable/opus・翔さん依頼）: slope 凍結・
  min() 実効挙動の正文化・alert イベント分離・turn 系列保存・window_error/compaction 分離・
  スキーマ増補（both/started_at/value_kind/run_meta）・ヒステリシス・T_abs 系譜注記・§9-1 新設。
  EV-008 側は prereg v0.2 で shadow 評価・replay 較正・判定手続き凍結・橋渡し条項・handoff 契約。
  裁定= reviews-159-L19/ADJUDICATION-r2.md
- r3（2026-08-23・kimi-k3/glm-5.3= CUMULATIVE GWC + grok-4.6= 狭い NO-GO〔B1 のみ〕→指定修正の
  逐語適用+マイクロ確認で RESOLVED — cumulative GO）: **L1-9 上流レビュー PASS・blocking 残0**。
  裁定= reviews/ADJUDICATION-r3-FINAL.md
- v0.5（2026-08-25・Alpha）: EV-008 完了・default-on GO 宣言（案A・翔さん決裁）を §0 として反映。
  設計制約 C-1（per-model 適用判定・grok 第3類型）/ C-2（blind-path ガード）/ C-3（ホスト圧縮同居）を
  昇格。§5 T_abs に実走値 80k/50% を注記・§7 を実施済みへ更新。数字の正= EV008-FINAL-REPORT.md +
  step5-reconcile.py（必須併記3点は省略禁止のまま転記）
