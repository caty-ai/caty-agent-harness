# DESIGN: #159 overflow sentinel — 文脈圧力の実測で task-runner を発火する

status: **v0.6.2**（2026-08-29・Alpha・外部レビュー採用2件〔@pm25coder〕の条文化 + D4 閾値注入点の
設計凍結（数値は P2 窓プローブ待ちで保留）・L1-9 異種5席 r1→r2 delta 全反映・Codex マイクロ確認待ち・
サイズ H。直前の凍結版= v0.5.4〔§10。v0.5.3 表記のまま header 未更新だった誤記を本版で訂正〕）
inputs: PILOT.md（訂正節含む）/ REPORT-runtime-context-survey.md / REPORT-pattern4-rootcause.md /
REPORT-hermes-provider-layer.md / REPORT-hermes-provider-deep-research.md / REPORT-qwen38-artifacts.md /
#159 clarify 決裁5点 / L1-9 r1〜r3 裁定（reviews/ADJUDICATION-r1〜r3-FINAL.md）/
セロ一次証言（maintainer 聞き取り 2026-08-23・非公開記録）/
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
  0発火/**669** sentinel ターン〔一次ログ sentinel-events.jsonl の turn イベント実数
  102+116+205+246・2系統の独立再計数で一致〕= 95%上限 ≈0.45%/turn。FINAL-REPORT 当初の「約770」
  は出所不明のため棄却・同報告に訂正記録済み）
- **第3類型（grok・descriptive）**: 発火型だが経済メリットなし — 4/4 発火→分解→完走（機構の頑健性を
  別ランタイムで実証）する一方、bare が極めて安く（763k〜2.4M）ペア比中央値 **2.145 >1.0**。
  「**成長型×低 bare 単価= default-on 不向き**」。
- 副腕1（64k 強制オーバーフロー・プロキシレーン）= **継続中**（GO 4条件の対象外・完了時は追補扱い）。

**EV-008 結果から昇格する設計制約（v1 実装に対して規範）**:
- **C-1 per-model 適用判定**: default-on の適用範囲はモデル別経済プロファイルで決める。発火・分解・
  正答維持が正しく動くこと（grok で実証済み）は導入判断と独立 — 判断は **bare 対比の経済**で行う。
  grok 型（成長型×低 bare 単価）には default-on を適用しない。**C-1 は配備適格性（enablement）の
  ポリシーであり、発火時の class prior の再導入ではない** — §4 の発火述語は unknown 一択・実測のみの
  まま、§9 の非目標（静的分類表の保守）も不変。
- **C-2 blind-path ガード**: per-turn usage の実値が得られない経路では sentinel を有効化しない。
  実測の盲目経路= glm/muse（shim 経由で per-turn usage 全ゼロ）・kimi（usage 非放出）。全ゼロ usage の
  検出時は起動拒否（または明示的 disabled 記録）とし、§3 の `tap_status: absent` と同様に
  「発火しなかった」と「見えていなかった」を区別可能な形でログに残す。
- **C-3 ホスト圧縮との同居**: 水位管理者は同時に1人（独自コンパクションを持つホストでは
  ①ホスト圧縮先行→sentinel 恒久不発火の飾り化 ②二重介入、の両リスク）。検知土台は既存
  （task_end の runtime_compaction / compaction_suspected・本走全走行で false 実測）。実装形
  （switcher config）の包含は実装 Issue の clarify で確定。

GO 宣言の射程= claude 系ランタイム + codex は「無発火・課金非上乗せ」の安全条件で同居可。
宣言文書の射程条項をそのまま引き継ぐ2点: **opus 帯（1M 窓・網羅読み）への一般化は外挿**であり
M5 は descriptive の post-GO 監視（PASS したが確証4条件には算入しない）。**qwen は GO 中立** —
発火時は prior 設計の差し戻し材料であって宣言の撤回条件ではない（harmful 条項がバックストップ）。
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
   output_tokens, model, runtime, ctx_window_claimed?, tap_status, raw_usage?}`
  - **`runtime`（v0.6.1 追加）**: ランタイム**ファミリー**の安定識別子（例 `claude-code` / `codex` /
    `agy`。バージョンを含めない — バージョン更新は regime 変更ではない）。§4 のリセット判定は
    `model_identity = canonical(model)`（小文字化+trim・config の任意 alias map 適用後）と
    `runtime`（ファミリーそのまま）で行う。**どちらかのフィールドが欠けたターンでは比較しない**
    （リセットも発生させない）。
  - **`raw_usage?`（v0.6.1 追加）**: 正規化前の生 usage オブジェクト（§3-1 derived 検査と
    スキーマ署名の材料。turn ledger に保存される — §6 turn 系列の常時保存に含める）。
    **`drift_reference ∈ {independent, derived}` のランタイムでは必須**（無ければ検査が成立しない）・
    省略可は `none` 申告時のみ（r2 Grok N2）。
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

### 3-1. 計器の第3状態: tap_drift（外部レビュー採用 @pm25coder・2026-08-27）

計器（tap）の状態は3つに区別する — ①正常報告 ②観測不能（`tap_status: absent` /
`no-cache-accounting` = 「見えていなかった」）③**計器が嘘をついた（tap_drift）**。①②は既存条文が
カバーするが、③には従来イベントが無かった。同一アダプタ+同一 model id のまま、供給側が静かに
別プロバイダ/別トークナイザに差し替わる事象（proxy/mirror fallback・routing 変更・base_url の
無告知付け替え）では、`input_tokens` の意味論がタスク中に変わり、per-runtime 正規化（§3 冒頭）では
捕捉できない系統バイアスが水位に入る — 正規化は tap 時点のアダプタ単位で行われるが、drift は
アダプタの**取得元の報告**の側で起きるため。

**リファレンスの独立性（r1 v0.6 の 5席収束 F1 を受けた正直な契約）**: 現行 §4 記載のランタイム
（claude stream-json / codex turn.completed / agy result）では、tap の取得元＝レスポンスの usage
オブジェクトそのものであり、**同一チャネルどうしの比較はトートロジー**（プロバイダ差し替えを原理的に
検出できない）。そこで adapter は capability **`drift_reference: independent | derived | none`** を
申告し、モードごとに検査の意味を変える（嘘の検出器を出荷するより、検出できる範囲を明示する）:

- **independent**（tap と provenance が独立な参照が有る — 例: レスポンス stream と別系統の
  provider usage/billing API）: 真の provider-drift 検査。
- **derived**（参照＝tap の取得元と同一のレスポンス usage オブジェクト。現行3ランタイムの想定値）:
  検査は2本に降格し、**その旨をイベントに刻む**（derived の counts を provider-drift の証拠として
  提示してはならない）:
  1. **正規化整合検査**: turn イベント発行時に使った**生 usage オブジェクトを turn ledger に保存**し、
     検査時に §3 の正規化規則を再適用して、発行済み `injected_t` と一致するかを照合
     （アダプタ正規化の退行・二重計上バグを検出）。
  2. **スキーマ署名検査**: 生 usage オブジェクトの**キー集合（sorted field-set signature）**を
     ターンごとに記録し、同一 regime epoch 内で署名が変われば `drift_kind: schema-change` の
     `tap_drift` を記録（プロバイダ/トークナイザ差し替えの多くはフィールド構成の変化として現れる —
     provenance に依存しない実検出力）。
- **none**: 検査不実施。タスクレベルの **`drift_reference_status: none`** として task_end に申告し、
  無言でスキップしない（`tap_status` には載せない — tap_status は「usage が見えるか」の語彙で、
  検査能力の語彙を混ぜない・r1 GLM F8/Grok F2）。

**突合述語（v1 で凍結する一意の定義・regime epoch は §4 のリセットで区切る）**:

```
cadence     : epoch 内で e = N_drift, 2·N_drift, … の各ターンで検査
              （参照欠落ターンも cadence を進める・イベントは出さない）
R_e         = epoch 内ターン ≤ e のうち**参照観測が取得できたターンの集合**
              （参照欠落ターンは cadence を進めるが、**両辺の和から対で除外**する —
              片側だけに計上すると欠落自体が偽の累積バイアスになるため・r2 Codex#1）
reported_cum_e  = Σ injected_t over R_e（tap が発行した正規化済み値の累積）
reference_cum_e = Σ ref_t over R_e（ref_t = independent なら独立参照から取得、
                  derived なら保存済み生 usage への正規化規則の再適用値 — 両辺は同一の
                  正規化・同一のキャッシュ基準を共有する construction で、基準不一致の
                  系統誤差を構造的に排除する）
signed_bias = reported_cum_e − reference_cum_e
bias_ratio  = signed_bias / max(reference_cum_e, 1)
drift_state = |bias_ratio| > θ_drift        # 方向非依存
tap_drift   は drift_state への「突入時」に1発（edge/episode-triggered・|bias_ratio| ≤ θ_drift
              へ戻ったら re-arm。tap_drift_count はエピソード数 — 検査周期数に依存しない）
schema-change 署名変化は独立のエピソードとして同スキーマで記録
```

- **検査の実行主体は core**: 両辺とも ledger 保存値（発行済み turn 系列と `raw_usage`）に対して
  core が評価する — アダプタ自身に自己採点させない（r2 GLM N2）。
- v1 の動作は**記録のみ**（発火・sentinel 無効化・ナッジはしない — D3「提案のみ」と整合。
  drift 実測が蓄積してから v2 で degrade 動作を検討する）。C-2（blind-path）とは非干渉 —
  drift は enablement を変えない。
- 位置づけ: §9-1 が警告する「系統バイアスは静かに入る」クラスの実装化であり、§6 イベント族の補完。
  独立参照が v1 の全ランタイムで欠けている（全席 derived）こと自体は許容される結果 — それは
  「@pm25coder 採用の文書化された縮小」であり、無言の縮小ではない（r1 Grok Q7 裁定）。

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
**ctx_window ≥ T_abs/w（製品既定 T_abs=80k・w=50% なら 160k）のモデルでは絶対項が常に先に効く**。相対項が主役になるのは
小窓モデル（64k 級・EV-008 の人工縮小腕を含む）のみ。「相対=あふれ射影用」という v0.3 の説明は不正確
だったため削除。

- **縮退規則**: ターン1= injected_1 単独を MA とみなす（N 未充足時は取得済み分の平均）。
  傾きは**ターン4（=K+1）から**（述語ブロックの `t−K 未取得なら slope 未定義` が正・kimi r3 NB-2）。
- **絶対閾値 T_abs の由来**: EV-006 で harness が注入を抑えた上界 20〜40k/turn の上端。
  1M 窓モデルで「浪費帯 112k/turn が窓比 11% で永遠に発火しない」盲点を塞ぐ（F2）。
- **auto-compaction を観測したら**（注入の急落で検出 or ランタイムイベント）: MA と傾きをリセットし、
  保留中のナッジは取り下げる（ランタイムが自衛した直後に分解を勧めない）。圧縮検出は v1 では
  ヒューリスティック（前ターン比 40% 超の急落）でよい — 誤検出のコストはナッジ1回の抑制のみ。
- **モデル/ランタイム変更を観測したら**（外部レビュー採用 @pm25coder・2026-08-27・v1 必須。
  順序と範囲は r1 v0.6 5席指摘で凍結）: 以下を**この順で**行う。

  ```
  ターン t の取り込み手順（regime 判定が最初・唯一のリセット・reset-before-fire）:
  1. 同一性比較: model_identity_t ≠ model_identity_{t-1} または runtime_t ≠ runtime_{t-1}
     （正規化は §3 の定義。欠落フィールドは比較しない=リセットなし）
  2. 変更なら regime リセット1回のみ:
     - regime_change_resets++ ・ 保留ナッジ取り下げ
     - MA・傾き・§3-1 の drift 累積器と cadence カウンタを全てクリア
     - ナッジのヒステリシスを再武装（軸ごとの提示済みフラグと前回発火水位をクリア —
       「タスクごと軸ごと1回」は「regime ごと軸ごと1回」に意図的に変わる。旧 regime の
       水位は新窓との比較に意味を持たないため）
     - モデルキーの config を全て再解決: ctx_window（§5 梯子・旧 ctx_window_claimed 破棄）+
       T_abs / w（§5-1 解決順を再実行 — これが無いと P2 の per-model 表が入った瞬間
       「旧モデルの閾値×新モデルの窓」になり §5-1 の writeback-only 約束が崩れる）+
       TTFB floor（§4-1 表の引き直し）
     - regime_change イベントを記録（§6・from/to と再解決結果を持つ）
  3. compaction ヒューリスティック（40% 急落）は regime 境界をまたいで評価しない
     （モデル差由来の注入急落を圧縮と誤分類しない）。ランタイム明示の compaction イベントが
     同ターンに来た場合は両方の観測を記録するが、状態リセットは1回
  4. ターン t を新 epoch のサンプル1として取り込み、当該ターンの述語評価は新 epoch の状態で
     行う（level 軸はサンプル1から・slope はサンプル K+1 から = 縮退規則の epoch 適用）
  ```

  根拠は EV-006/EV-008 の per-model プロファイルそのもの — 「同族でも読み方の regime が違う」
  （sonnet 選択読み vs opus 網羅読み・qwen on claude CLI）は実測済みであり、タスク途中のモデル切替
  （別モデルでの retry・プロバイダ側 fallback）後は、旧モデルのターンから計算した傾きは stale では
  なく**誤った regime** になる。バージョン揺れ・表記揺れによる偽リセット（slope 軸の無音盲目化）は
  §3 の正規化＋ファミリー比較で抑止し、§9-1 の alias fixture で検査する。
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

## 5. 閾値と ctx_window（D4: 製品既定 + config 上書き）

| パラメータ | 既定 | 由来 |
|---|---|---|
| N（移動平均窓） | 3 turns | pilot の bare 立ち上がり 2〜4 turn |
| T_abs（絶対水位） | **80,000 tok/turn** | EV-008 GO 実走値。設計時の初期値 40,000 tok/turn は較正候補 {40k, 80k, 120k} の下端として由来欄に残置。LITE Phase 0 replay で 40k は claude 系 bare のターン1即発火= 過敏と実測済み。**系譜注記（Fable r2）**: EV-006 の 20〜40k は harness の per-step fresh-context 注入量・sentinel の injected は累積プロンプト全体でレジームが異なる |
| w（窓比水位） | **50%** | bare sonnet L帯 定常 ~56% の近傍。**導出ではなく同域の初期値** — EV-008 は実走 50% で GO 成立（ライブ sweep は prereg v0.3 で replay 較正に置換） |
| M（射影ホライズン） | 10 turns | 保守的（v1 の誤発火コスト= ログ1行+ナッジ1回） |
| TTFB 床 | 90/150/240s + reasoning floor 表 + unknown=240s | Hermes 実装値 + hermes#89241 の逆張り |

**ctx_window の5段梯子**: config 明示上書き > HF config.json（公開モデル・**訓練上限≠提供窓に注意**、
過大方向は T_abs 併置で無害化） > opt-in の HF network cache rung（`CLAUDE_MODEL` を plain な HF repo id
として検証し、`https://huggingface.co/<model>/resolve/main/config.json` を stdlib `urllib` の 1 fetch /
hard 5s timeout で取得、`OVF_HF_CACHE_DIR` 配下へ flat な `sha256(model).json` を atomic write して
再読込に成功した場合のみ採用） > モデルカタログ > 保守既定 200k。採用段を `ctx_window_source` として
ログに記録し、network rung の source 名は fresh/cached とも `hf-network-cached` に固定する。
HF id / cache validation / cache I/O / fetch の失敗は warning を 1 行出して catalog/default へ fall through
する。128k 実窓モデルに 200k 既定が当たる過大方向の見逃しも T_abs が受ける。

### 5-1. per-model 閾値の注入点（D4 の残余 — 注入点は本版で凍結・数値は P2 窓プローブ待ち）

D4 の未決分= 「データ由来の per-model 閾値の数値」。数値の供給源となる **P2 窓プローブ**
（overflow-band の corpus-size ladder・封緘 p2 generator・sonnet 先行→opus。#159 2026-08-28
コメント参照）は走行待ちのため、**本版では数値を確定しない**。凍結するのは注入点の設計のみ:

- **解決順序（凍結）**: config 明示上書き > **per-model 閾値表**（model パターン → `{T_abs?, w?}` の
  部分上書き・欠けたキーは次段へ） > 製品既定（T_abs=80k / w=50%・§5 表）。
- **表のマッチングは決定論（凍結・r1 Codex#8）**: canonical 完全一致 > パターン（最長リテラル
  接頭辞が最specific）・同 specificity の重複は **config ロード時エラー**（実行時に黙って先勝ちしない）。
  未知キー・範囲外値もロード時に拒否する。**パターン文法も凍結**: glob の `*` のみ
  （`?`・文字クラス・ブレースは不使用 — 実装間で解釈が割れない最小文法・r2 Codex#8）。
- **C-1 との境界（r2 Grok F10）**: per-model 閾値表は発火の**較正**であり、C-1（配備適格性
  enablement）を変えない — 表にエントリがあることは default-on の根拠にならず、逆も然り。
- **config 明示上書きの ctx_window は regime 変更後も最上段として勝つ**（r2 Grok F11 の明文化 —
  run-level 上書きは操作者の明示指定であり、モデル切替はそれを取り消さない。意図的）。
- 採用段は**キー別**に fire / task_end の `run_meta` へ
  **`threshold_sources: {T_abs: config|per-model|default, w: config|per-model|default}`** として
  記録する（ctx_window_source と同じ思想 — どの段が勝ったかを後から復元できない値は較正に使えない。
  部分上書き `{T_abs: per-model, w: default}` が正規の状態なので単一 enum では復元不能・r1 5席収束）。
- **regime 変更時は本解決順を再実行する**（§4 手順2 — これが「P2 数値は writeback だけで入る」を
  成立させる条件。resolver を呼ぶのは task 開始時と regime 変更時の2箇所のみ）。
- per-model 表は **config データ（コード定数ではない）**とし、P2 の数値確定は表の writeback として
  入る — 発火述語（§4）にも解決順序にも触れないため、コード変更・再設計を要しない。
- 空の per-model 表は正常（= 全モデル製品既定）。P2 完了までは空のまま出荷する。
- tap_drift の cadence（N_drift）・バイアス閾値（θ_drift）も同じ config 面に置く（§3-1。数値既定は
  実装 Issue で仮置きし、drift 実測の蓄積後に較正 — per-model 表と同じ「注入点先行・数値後追い」の型）。

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
           value_kind: measured|estimated, threshold_hit?: abs|ratio|both（level crossing 時のみ）, ctx_window, ctx_window_source,
           slope, projection_turns, decision: nudge, nudge_disposition: shown|suppressed|shadow,
           model, runtime, tap_status, run_meta: {arm?, seed?, shuffle_seed?, T_abs, w, N, M, K,
           threshold_sources: {T_abs, w}}（§5-1 のキー別帰属・v0.6.1 で literal に明記）,
           schema_version}
alert:    {ts, task_id, turn_idx, ttfb_ms, floor_applied, model, runtime, schema_version}
           （TTFB は fire と別イベント。Grok r2#5: codex の「発火0」合格判定を alert が汚染しないため）
tap_drift: {ts, task_id, turn_idx, drift_kind: bias|schema-change,
           drift_reference: independent|derived, reported_cum_tokens, reference_cum_tokens,
           signed_bias, bias_ratio, threshold, cadence_turns, model, runtime, schema_version}
           （§3-1。fire / alert と独立の countable イベント — 発火統計を汚染せず、「計器が嘘をついた」
           を後から数えられる形で残す。エピソード単位（突入時1発・re-arm 後に再カウント）。
           derived 由来の counts を provider-drift の証拠として扱わないこと。v1 は記録のみ）
regime_change: {ts, task_id, turn_idx, from_model, to_model, from_runtime, to_runtime,
           resolved: {ctx_window, T_abs, w, ttfb_floor},
           sources: {ctx_window_source, threshold_sources},
           drift_reference: independent|derived|none（新 regime の検査能力・r2 Codex#6/GLM N3 —
           capability が regime 間で変わっても履歴が残る唯一の記録）, schema_version}
           （§4 手順2。発火の無い regime でも閾値解決の履歴が復元できる唯一の記録 —
           マルチ regime タスクの較正材料）
task_end: {ts, started_at, task_id, outcome: completed|overflowed|decomposed|aborted,
           window_error: bool, runtime_compaction: bool, compaction_suspected: bool
           （Opus r2 B3: API 拒否とランタイム自衛を混同しない・ヒューリスティック検出は別フィールド）,
           total_tokens, injected_summary: {max, last3_mean}, fired_turns: [..], alert_turns: [..],
           regime_change_resets: int（model/runtime どちら由来かは regime_change イベントの from/to で
           復元・r1 Codex#7）, tap_drift_count: int（エピソード数・§3-1）,
           drift_reference_status: independent|derived|none（§3-1 の検査能力申告 — tap_status とは
           別語彙。**複数 regime のタスクでは最弱値**（none < derived < independent）を報告し、
           regime ごとの実値は regime_change イベントで復元する・r2 Codex#6）,
           nudge_disposition_final, tap_status, run_meta, elapsed_s, schema_version}
```

**ナッジのヒステリシス（Fable r2・v0.6.2 で regime 単位に改定）**: nudge は **regime ごと（§4 の
リセットで再武装）**・軸ごとに1回。再提示は MA が前回発火時からさらに `+10% × ctx_window` 上がった
時のみ（連打による無視学習とログ肥大の防止）。v0.5.4 の「タスクごと」は §4 の regime リセット導入に
伴い regime 単位へ意図的に変更（r2 で Codex/GLM/Grok が独立に §4 との矛盾を指摘・§4 が正）。

- **誤発火の定義はコストで行う**: 発火+completed は誤発火ではない（EV-006 の本命ケースは
  「完走するが4〜6x高い」）。判定は task_end の total_tokens と EV-008 の対照腕（別紙）で行う。
- 非発火タスクも task_end を1行残す（見逃し検証の対照・tap_status 込み）。
- 置き場: **task-runner ledger への合流を第一候補**（task_id で followup 結合が壊れない・Grok r1）。
  独立ファイルにする場合は「ledger 実装前に sentinel を単体計測するため」という理由を実装 Issue に明記。
- attempt receipt にも `first_byte_at`（null 可）を必須化（CLAUDE_BIN 事故で最も欠けていた1フィールド。
  #162 のスキーマと語彙を揃える）。

## 7. EV-008（D5）— 事前登録は別紙・**実施済み（結果は §0）**

同梱の `EV008-PREREG.md` は**封緘前のローリングドラフト snapshot（DRAFT v0.3・3席 delta 未実施時点）**
であり、封緘済みの実走正本ではない。封緘版= `EV008-PREREG-DRAFT.md` SEALED v1.0 + r4/r5 裁定 +
モジュール封印台帳（私設リグ・非公開・README の公開方針どおり）。実走完了 2026-08-25。結果と GO 宣言は
§0、確定数字は experiments/ev006/EV008-FINAL-REPORT.md が正。設計時の骨子（記録として保持）:
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
- TTFB 床の tier キー= 前 monitored run の last injected MA（v0.5.3 実装 delta で旧「前ターン」表現を訂正）
- tap_drift 突合の golden-file テスト（§3-1。固定入力で: バイアス方向2通りの検出・閾値未満の非検出・
  **エピソード意味論**（持続 drift で毎周期カウントしない・re-arm 後の再カウント）・ゼロ参照分母・
  **derived/independent の別が正しくイベントに刻まれる**こと・`drift_reference_status: none` の申告・
  **同一 provenance で等値でも「independent 突合 PASS」を主張しない**こと・キャッシュ包含/排他の
  基準不一致 fixture（両辺同一正規化の construction が守られているか）・schema-change 署名検出・
  **参照が間欠欠落する fixture**（欠落ターンが両辺から対で除外され偽バイアスを作らない= R_e 検証）・
  **capability が regime 間で変わる fixture**（task_end= 最弱値・regime_change に per-regime 値））
- regime リセットの unit テスト（§4。タスク途中の model 切替 fixture で: MA/slope/drift 累積器の
  クリア・保留ナッジ取り下げ・ヒステリシス再武装・ctx_window+T_abs/w+TTFB floor の**全再解決**・
  `regime_change` イベント発行・`regime_change_resets` 集計。**alias/バージョン揺れ fixture で
  リセットが起きない**こと・**model 変更と compaction 同ターン fixture でリセットが1回**であること・
  reset-before-fire= 切替ターンの述語評価が新 epoch 状態で行われること・**per-model 表の2エントリ間を
  タスク途中で切り替える fixture**・**ターン1がリセットとして数えられない fixture**（比較対象なし=
  no-op）・**identity フィールド欠落 fixture**（欠落側では比較もリセットも発生しない））
- 閾値解決順序のテスト（§5-1。config > per-model 表 > 既定の3段・部分上書きの**キー別**
  `threshold_sources` 記録・同 specificity 重複と未知キーのロード時拒否）
- イベント族の分離アサーション: **tap_drift のみ有る（fire 無し）タスクの task_end が fires=0 を
  報告する**こと（codex「発火0」型の合格判定を汚染しない・r1 Codex#10）
- ledger fold 契約: tap_drift / regime_change は v0.5.4 の bounded fail-open fold の**対象イベント型に
  明示追加**する（未知型として黙って落とされない・r1 Grok F8）
- **実装 Issue には外部レビュー由来2件（§3-1・§4 モデル変更リセット）のクレジットとして
  @pm25coder（harness#159 2026-08-27 コメント）を仕様として明記する**（翔さん決裁 2026-08-29）

## 10. レビュー履歴

- r1（2026-08-23・kimi-k3/grok-4.6/glm-5.3・**NO-GO/NO-GO/GWC**〔v0.5 までの本節が席順に対して
  GWC/NO-GO/NO-GO と誤記・ADJUDICATION-r1 の実票に合わせ訂正 2026-08-25〕）: F1 述語一意化→§4 /
  F2 絶対閾値併置→§4-§5 / F3 EV-008 凍結→別紙 / F4 TTFB alert-only→§4-1 /
  F5 ログ分離→§6 / F6 細部→§3-§5。裁定= reviews/ADJUDICATION-r1.md
- v0.3 追加入力: セロ一次証言（Why 節・ナッジ中身・v2 軸・非目標）・翔さん指示「Why を入れる」
- r2（2026-08-23・正席3= NO-GO/GWC/NO-GO + 参考3= codex/fable/opus・翔さん依頼）: slope 凍結・
  min() 実効挙動の正文化・alert イベント分離・turn 系列保存・window_error/compaction 分離・
  スキーマ増補（both/started_at/value_kind/run_meta）・ヒステリシス・T_abs 系譜注記・§9-1 新設。
  EV-008 側は prereg v0.2 で shadow 評価・replay 較正・判定手続き凍結・橋渡し条項・handoff 契約。
  裁定= reviews/ADJUDICATION-r2.md
- r3（2026-08-23・kimi-k3/glm-5.3= CUMULATIVE GWC + grok-4.6= 狭い NO-GO〔B1 のみ〕→指定修正の
  逐語適用+マイクロ確認で RESOLVED — cumulative GO）: **L1-9 上流レビュー PASS・blocking 残0**。
  裁定= reviews/ADJUDICATION-r3-FINAL.md。**来歴注記（2026-08-25）**: grok マイクロ確認の逐語ログ
  （裁定が参照する prompt-grok-confirm.md への直答）はファイルとして非保全 — RESOLVED 判定の根拠は
  当時の裁定記録の記載のみ。誇張を避けるためこの限界を明示する
- 記録の読み方: レビュー記録内の「EV-007 / EV007-PREREG」は本実験 EV-008 の当時の作業名（r 系裁定は
  改番前に書かれた逐語記録のため未編集で保持）
- v0.5（2026-08-25・Alpha）: EV-008 完了・default-on GO 宣言（案A・翔さん決裁）を §0 として反映。
  設計制約 C-1（per-model 適用判定・grok 第3類型）/ C-2（blind-path ガード）/ C-3（ホスト圧縮同居）を
  昇格。§5 T_abs に実走値 80k/50% を注記・§7 を実施済みへ更新。数字の正= EV008-FINAL-REPORT.md +
  step5-reconcile.py（必須併記3点は省略禁止のまま転記）
- v0.5.1（2026-08-25・Alpha・merge 前公開ゲート異種5席〔codex/glm/grok/gemini/muse・writer=Alpha と
  全席異系統〕の指摘反映）: §7 prereg 来歴を実物（封緘前 snapshot）に訂正 / §10 r1 票の席割り誤記訂正・
  旧作業 dir パス修正・r3 確認ログ非保全の来歴注記・EV-007 改番注記 / §0 qwen ターン数を内訳整合値
  671 に訂正（≈0.45%/turn）・GO 射程に opus 外挿・qwen GO 中立を明記 / C-1 に「class prior ではない」
  明確化 / §5 T_abs 既定を TBD 化・w 行の時制整合 / 同梱 prereg のアカウント運用情報 redact・README
  現行化・LITE に位置づけバナー（各席の out= レビュー記録として別途保全）
- v0.5.2（2026-08-25・Alpha・delta レビュー〔codex/grok/glm〕の flip 条件反映）: §0 qwen ターン数を
  一次ログ実数 **669**（102+116+205+246・2系統の独立再計数一致・「約770」は出所不明で棄却）へ再訂正 /
  prereg の残存リセット日付と本垢運用記述を redact し、notice を「redact したもの/意図的に保持した
  方法論」の列挙形に精密化 / README の
  「3席 cumulative GO」を裁定記録ベースと明示（r3 確認ログ非保全の開示と整合）/ §4 の「既定なら 80k」と
  §5 見出しを TBD 化と整合 / §10 r1 訂正注記の版表記を v0.5 までに修正
- v0.5.3（2026-08-25・#180 実装 writeback）: §5 の製品既定を T_abs=80k / w=50% に確定。
  v1 claude-code integration は monitored run ごとの terminal record として `attempt_end` を emit し、
  task-level `task_end` は ledger-confluence follow-up へ延期する。nudge delivery は next-step boundary のため、
  発火 attempt で task が終了した場合は nudge 未配送となる。TTFB v1 は run-start→first assistant byte のみで、
  inter-turn stall detection は passive stream で request boundary を観測できる joint-design follow-up へ延期する
- v0.5.4（2026-08-27・#187 application note）: `sentinel-events.jsonl` を task-runner sole-writer の
  per-task `ledger.jsonl` へ bounded・fail-open に fold し、driver の実 terminal state から distinct な
  task-level `task_end` と atomic `task-end.json` receipt を生成する ledger-confluence を適用。
  `window-error` は infra として fresh-session retry し、retry を焼き切った最終 driver も `window-error` の場合だけ exhausted DLQ を `overflowed` に写像する。
  outcome ownership は裁定済み設計として FINAL burned attempt の分類に属し（codex r2 の any-attempt derivation は棄却）、途中に overflow evidence があっても最終 attempt が non-window failure の mixed run は `aborted` とし、overflow evidence は folded `attempt_end` records に保持する。
  また `maximum context length` / `context window` は error-shape guard 付きのままとする（main の unguarded arm に対する deliberate prose-hardening であり、retry fix 後のコストは outcome label だけで retry budget には影響しない）。
  per-run `attempt_end` と monitor の schema/state は変更しない。
- v0.6（2026-08-29・Alpha・**外部レビュー採用の条文化 + D4 注入点凍結**）: @pm25coder の設計レビュー
  （#159 comment 2026-08-27・external, association NONE・採用決裁= 翔さん 2026-08-28 返信
  comment 5457427311）から採用2件を条文化 — ①tap_drift= 計器の第3状態「計器が嘘をついた」
  （§3-1 新設・§6 イベント追加・v1 は記録のみ）②モデル/ランタイム変更時の MA/slope リセット
  （§4・auto-compaction リセットと同型・フィールド比較のみ・v1 必須）。あわせて D4 の残余を
  §5-1 として凍結: per-model 閾値の**注入点**（解決順序・threshold_sources・config データ化）のみ
  確定し、**数値は P2 窓プローブ（overflow-band ladder）完了後の writeback へ保留**。§9-1 に
  対応する検査項目3点とクレジット明記義務を追加。header の v0.5.4 未反映誤記を訂正
- v0.6.1（2026-08-29・Alpha・**L1-9 異種5席 r1 の blocking 反映**）: r1= Codex GPT-5 系 **NO-GO** /
  GLM 5.3 **NO-GO** / Grok 4.6 **NO-GO** / Gemini 3.7 Flash **GO-w/c** / Muse Spark 1.2 **GO-w/c**
  （writer=Alpha fable-5 と全席異系統・blind 並列・fresh context・read-only。Grok 席に coverage-matrix
  併任= DW 全項 covered/unclear 2・scope creep 0）。5席収束の急所を全て条文化:
  ①§3-1 突合契約の全面書き直し — `drift_reference: independent|derived|none` capability・derived の
  正規化整合+スキーマ署名検査への明示的降格（Grok Q7 裁定・pm25coder 採用の文書化された縮小）・
  一意の突合述語（累積基準/式/ゼロ分母/エピソード意味論）②§3 turn schema に `runtime`+`raw_usage?` 追加・
  ID 正規化（alias 揺れの偽リセット抑止）③§4 リセットの順序凍結（identity 先行・リセット1回・
  compaction 非交差・reset-before-fire・ヒステリシス regime 単位再武装・**T_abs/w/TTFB floor 含む
  全 model-keyed config の再解決**= P2 writeback-only 約束の成立条件〔Codex#5/GLM F3/Grok F5〕）
  ④§5-1 キー別 `threshold_sources`+表マッチング決定論 ⑤§6 に regime_change イベント新設・fire run_meta
  literal へ threshold_sources 明記・task_end を regime_change_resets/drift_reference_status に整理
  ⑥§9-1 敵対 fixture 群+fires=0 非汚染アサーション+ledger fold 明示追加。
  裁定= reviews/ADJUDICATION-r1-v06.md・席 out 原本= 私設 experiments/ev006/reviews-159-v06/（保全済み）
- v0.6.2（2026-08-29・Alpha・**r2 delta の残指摘 全反映**）: r2= Gemini GO / Muse GO / GLM GO /
  Grok GO-w/c / Codex NO-GO（狭い3点）。採用: ①§3-1 突合和を **R_e（参照取得ターン集合）上のペア和**に
  固定（間欠欠落が偽バイアスを作る経路を封鎖・Codex#1）②§6 ヒステリシスを regime 単位に条文同期
  （Codex/GLM/Grok 独立指摘・§4 が正）③regime_change に drift_reference・task_end は複数 regime で
  最弱値（Codex#6/GLM N3）④raw_usage を derived/independent で必須化（Grok N2）⑤パターン文法凍結=
  glob `*` のみ（Codex#8）⑥検査主体= core・ledger 値上で評価（GLM N2）⑦C-1 境界と run-level
  ctx_window 上書きの明文化（Grok F10/F11 NB）⑧§9-1 に fixture 4種追加（間欠参照/capability 変化/
  ターン1/identity 欠落）。裁定= reviews/ADJUDICATION-r1-v06.md 追記
