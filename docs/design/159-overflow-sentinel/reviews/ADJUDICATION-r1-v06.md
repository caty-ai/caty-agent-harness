# L1-9 設計レビュー裁定（r1）— #159 DESIGN v0.6 DRAFT（外部レビュー採用の条文化 + D4 注入点）

2026-08-29 / 裁定者= Alpha（writer・票に数えない） / 対象= DESIGN v0.6 DRAFT（v0.5.4 との delta）
体制= 異種5席・blind 並列・fresh context・read-only（高リスク= 対外公開 docs・L1-11）。
writer= Alpha（fable-5）のため Opus 席は同系統回避（loom-seats の codex-sol writer 前提 panel は
流用せず・writer note 適用）。

## 席と票

| 席 | requested | actual（自己申告） | verdict | 納品 |
|---|---|---|---|---|
| Codex | codex-sol (GPT-5.6) | OpenAI Codex GPT-5 系（版数非開示） | **NO-GO**（flip 6条件） | out-codex.md（stdout 捕捉） |
| GLM | glm-5.3 | glm-5.3 | **NO-GO**（狭い・flip 安価） | glm.md（正式ファイル納品） |
| Grok | grok-4.6 | Grok 4.6 (xAI) | **NO-GO**（+coverage-matrix 併任） | out-grok.md |
| Gemini | gemini-3.7-flash-high | Gemini 3.7 Flash | GO-with-concerns（flip 4条件） | out-gemini.md |
| Muse | muse-spark-1.2-contributor | Muse Spark（自己申告） | GO-with-concerns（F1=CRITICAL） | muse.md（正式ファイル納品） |

席 out 原本の保全先= 私設 `experiments/ev006/reviews-159-v06/`（本リポの公開方針どおり非同梱・
要請あれば提示）。

## 収束（採用確定級・独立一致）

1. **突合契約の未凍結**（5/5）: 「直近レスポンスの usage オブジェクト」は tap の取得元と同一チャネル＝
   トートロジー比較になり、名指しした失敗（プロバイダ差し替え）を検出できない。式・累積基準・
   ゼロ分母・再発火規則も未定義 → §3-1 全面書き直し（drift_reference capability・derived の明示的
   降格・一意の突合述語）。Grok Q7 の「文書化された縮小 > 検出できない検査の出荷」裁定を採用。
2. **turn schema に runtime 不在 + ID 正規化なし**（Codex#2/GLM F2/Grok F3/Gemini F2）: 生文字列
   比較は alias/バージョン揺れで連続偽リセット→slope 軸の無音盲目化 → §3 に runtime/正規化を追加。
3. **リセットが ctx_window しか再解決しない**（Codex#5/GLM F3/Grok F5）: P2 の per-model 表が入った
   瞬間「旧モデル閾値×新モデル窓」になり §5-1 の writeback-only 約束が崩れる → §4 手順2で
   T_abs/w/TTFB floor 含む全 model-keyed config を再解決。
4. **順序・compaction 干渉・ヒステリシス範囲の未記述**（Codex#3/GLM F4-F5/Grok F4/Gemini F3）→
   §4 に4段の取り込み手順を凍結（identity 先行・リセット1回・境界跨ぎ heuristic 禁止・
   reset-before-fire・regime 単位の再武装）。
5. **threshold_source 単一 enum の帰属不能 + §6 literal 不在**（5/5）→ キー別 threshold_sources・
   fire run_meta literal 明記・regime_change イベント新設（発火の無い regime の解決履歴）。

## 単独指摘の採用

- GLM F9（drift 累積器×リセット干渉）→ §4 手順2でクリア対象に明記
- GLM F8/Grok F2（tap_status への検査能力の混載）→ drift_reference_status を別語彙化
- Codex#6（cadence/エピソード意味論）→ §3-1 述語（edge/episode-triggered・re-arm）
- Codex#7（model_change_resets の名前が範囲を過小表現）→ regime_change_resets へ改名
- Codex#8（表マッチング非決定）→ §5-1 決定論（完全一致>最specific・重複=ロード時エラー）
- Codex#9/Muse（§9-1 の検査が主要失敗を素通し）→ 敵対 fixture 群へ拡張
- Codex#10 NB（fires=0 非汚染アサーション）/ Grok F8（ledger fold の未知型ドロップ）→ §9-1 に追加

## 不採用・保留

- Gemini F4 後段の「threshold_source を top-level へ昇格」: per-key 化（収束案）で解消するため
  昇格はしない（run_meta 内で完結）。
- 数値既定（N_drift/θ_drift）の確定要求は無し（全席が owner 決裁の保留を尊重）— 実装 Issue で
  仮置き・較正後追いのまま。

## 評定

**r1= NO-GO 3 / GO-w/c 2 → blocking 全反映の v0.6.1 を作成し、5席 delta（RESOLVED 表+累積 verdict）
で確認する。** 骨格（採用2件の方向・log-only・config 表・3 Issue 分割・P2 保留）への異論は 0。

## r2 delta（対象 v0.6.1・同5席・自席 r1 findings の RESOLVED 表+累積 verdict 様式）

| 席 | verdict | 残指摘 |
|---|---|---|
| Gemini | **GO** | 全 RESOLVED・新規 0 |
| Muse | **GO** | F1-F9 全 RESOLVED・新規 0 |
| GLM | **GO** | 全 RESOLVED・非blocking nit 3（N1 ヒステリシス条文同期 / N2 検査主体 / N3 capability 履歴） |
| Grok | **GO-with-concerns** | F1-F6 RESOLVED・stay-NO-GO 解消・N1 ヒステリシス / N2 raw_usage 必須化・NB F10/F11 |
| Codex | **NO-GO**（狭い3点） | ①参照間欠欠落のペア和未定義 ②§6 ヒステリシス条文矛盾 ③capability の regime 間履歴。他7項 RESOLVED・「方向は健全」明言 |

**v0.6.2 で全採用**（blocking/nit を問わず — Codex③=GLM N3、Codex②=GLM N1=Grok N1 の独立収束）:
R_e ペア和 / §6 regime 単位同期 / regime_change.drift_reference + task_end 最弱値 / raw_usage 必須化 /
パターン文法 glob `*` のみ / 検査主体= core / C-1 境界・ctx_window 上書きの明文化 / §9-1 fixture 4種追加。
→ **Codex 席への単一論点マイクロ確認で cumulative GO を確認して凍結**（r3-FINAL の grok B1 と同型手続き）。

## r3/r4 マイクロ確認（Codex 席のみ・単一論点）

- r3（対象 v0.6.2）: 3点中 **2 RESOLVED**・残1= regime_change.drift_reference が新 regime の値のみで
  初回 regime の記録が消える（「全 regime 復元可能」が複数 regime タスクで偽）→ NO-GO
- v0.6.3: drift_reference を **{from, to} ペア**に（初回= 最初のイベントの from・以降= 各 to・
  変更なしタスク= task_end 値）
- r4（対象 v0.6.3・one-hunk diff）: blocker 3 **RESOLVED** —
  **CUMULATIVE VERDICT: GO for freezing v0.6.3 as the three-issue baseline**（本文ログ= 私設保全
  out-codex-micro.md / out-codex-micro2.md）

## 最終評定

**L1-9 設計 delta レビュー PASS（5席 GO 系で収束・blocking 残 0）**:
Gemini GO（r2）/ Muse GO（r2）/ GLM GO（r2）/ Grok GO-with-concerns（r2・懸念 N1/N2 は v0.6.2 で
反映済み）/ Codex GO（r4 cumulative）。**v0.6.3 を凍結版とし、実装 Issue 3本（①regime リセット S
②tap_drift M ③閾値注入点 M）の設計基線とする。** D4 の数値は P2 窓プローブ完了後に owner 決裁+
writeback のみで確定（clarify 決裁 2026-08-29・再レビュー不要）。

- requested/actual: codex-sol（自己申告 OpenAI Codex GPT-5 系）/ glm-5.3 / grok-4.6 /
  gemini-3.7-flash-high / muse-spark-1.2（Contributor 枠・公開文書のみ）。writer= Alpha（fable-5）—
  全席と異系統・self-approve なし。coverage-matrix= Grok 席（DW 全項 covered/unclear 2→v0.6.1 で
  解消・unrequested= scope creep 0）。
