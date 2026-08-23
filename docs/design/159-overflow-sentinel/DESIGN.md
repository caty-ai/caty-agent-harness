# DESIGN: #159 overflow sentinel — 文脈圧力の実測で task-runner を発火する

status: DRAFT **v0.4**（2026-08-23・Alpha・L1-9 r2（正席3+参考3）反映版・r3 delta 待ち・サイズ H）
inputs: PILOT.md（訂正節含む）/ REPORT-runtime-context-survey.md / REPORT-pattern4-rootcause.md /
REPORT-hermes-provider-layer.md / REPORT-hermes-provider-deep-research.md / REPORT-qwen38-artifacts.md /
#159 clarify 決裁5点 / L1-9 r1 裁定（reviews-159-L19/ADJUDICATION-r1.md・F1〜F6）/
セロ一次証言（family-vault 20_projects/family-os-external-proof/cero-hearing-task-runner-20260823.md）
関連: harness#162（zero-output attempt の事後分類・早期 DLQ）/ EV-008 事前登録= 別紙 `EV008-PREREG-DRAFT.md`

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
| T_abs（絶対水位） | 40,000 tok/turn（**較正候補 {40k, 80k, 120k}・EV-008 replay で確定**） | EV-006 harness 上界の上端（F2）。**系譜注記（Fable r2）**: EV-006 の 20〜40k は harness の per-step fresh-context 注入量・sentinel の injected は累積プロンプト全体でレジームが異なる。40k は過敏側（200k 窓の実質全タスクが中盤で跨ぐ）の可能性があり、既定の最終確定は較正に委ねる |
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

## 7. EV-008（D5）— 事前登録は別紙

正本= `EV008-PREREG-DRAFT.md`（翔さん決裁対象）。骨子のみ:
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
