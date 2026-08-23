## Verdict

**NO-GO**（累積評定・ただし文書レベルの小修正のみで解消可能・設計骨格・D1〜D5 の構造に再審は不要・delta round 3 または writer 修正+裁定者確認で足りる）。

r1 blocking findings の判定（GLM 席が r1 で直接担ったのは F1/F3/F4/F6。累積評定として F1〜F6 全てを判定）:

| r1 finding | 判定 | 根拠（v0.3 どこで解消されたか） |
|---|---|---|
| F1 発火述語の一意化 | **RESOLVED** | §4 に唯一の述語（level OR slope・結合規則1文・縮退規則・送信直前は v2 降格の物理根拠付き）+ §3 tap 契約の排他加算・正規化。slope の計算系列だけ未指定（非ブロッキング #1） |
| F2 絶対閾値の併置 | **RESOLVED** | §4 の OR 二本立て + §5 の由来表。w の由来も「導出ではなく初期値」と正直に書き直された（Kimi r1 指摘に対応） |
| F3 EV-007 事前登録の凍結 | **PARTIALLY RESOLVED** | 別紙化・定義凍結・強制オーバーフロー副腕・モデル別基準・B/C 入れ子・qwen 腕・env 凍結はすべて反映。ただし **mid-task handoff 契約が未整備のまま auto-enqueue 腕が存在**（新ブロッキング B1）、**false fire 定義に欠陥**（B2）、**sweep 選定規則が実行不能**（B3） |
| F4 TTFB alert-only | **RESOLVED** | §4-1 検出+ログ+alert のみ・kill しない・unknown=最長床 240s（「未知は殺さない側」へ整合）・#162 との所有境界明記・SSE ping 除外が tap 契約に条項化 |
| F5 ログ分離 | **RESOLVED** | fire/task_end 分離・in-place 禁止・axis/nudge_disposition/tap_status/ctx_window_source/total_tokens 揃備・誤発火をコストで定義・ledger 合流第一候補。採用欄の started_at が落ちているが ledger join で代替可（非ブロッキング #2） |
| F6 細部 | **RESOLVED** | 正規化規則・compaction で MA リセット+nudge 抑制・prior は unknown 一択・出所フィールド・schema_version すべて反映。Issue の Files-to-touch 訂正は埋め込み資料からは検証不能（非ブロッキング #6 で確認要求） |

NO-GO の理由を一言で: 設計本文（DESIGN v0.3）は GO 取れる水準まで到達したが、**決裁に上がる直前の事前登録書に「承認側へ偏る指標定義」「実行不能な選定規則」「設計自身が v2 前提条件とした機構の実験特例化」** があり、事前登録の存在意義（封緘後に直せない）からこれらは決裁前に直すべきだから。

## New blocking findings

L1-3 ratchet に従い、全て「埋め込み資料から示せる欠陥」または「未達のゲート基準」である。

**B1. auto-enqueue 実験特例が mid-task handoff 契約なしで走る（未達ゲート基準＋設計内矛盾）**
r1 裁定 F3 の採用リストに明記された「**auto-enqueue 腕には mid-task handoff 契約を §5 に新設**」が v0.3 に存在しない（§5 は閾値表になり、契約は §8 で v2 に「定義してから」と明記されたまま）。一方 EV-007 主グリッドの sentinel 腕は「v1 実装+**auto-enqueue on の実験特例**」で、48本の主比較のこの腕の挙動（発火時に現セッションを中断するのか・成果物をどう引き継ぐのか・文脈をどう蒸留するのか）がどこにも定義されない。これは (a) r1 の採用事項 未達、かつ (b) 設計自身の前提（§6「v1 は提案のみ」・§8「契約を定義してから」）と事前登録が矛盾する、の二重の欠陥。主比較腕の再現性がないまま決裁・実行には出せない。
**最小修正**: (i) 最小の handoff 契約（中断 semantics・成果物引き継ぎ・蒸留）を設計に新設する、または (ii) EV-007 の sentinel 腕を v1 設計どおり nudge-only で走らせ auto-enqueue 評価を契約整備後の別 EV に移す。(ii) の方が diff が小さく設計と整合する（代償：haiku の持続効果は「弱いモデルがナッジに従えるか」が機構になるが、それ自体が v1 の問い）。

**B2. 凍結された false fire 定義が「有害な不要発火」を計上から除外する（実証済み欠陥・承認バイアス方向）**
凍結定義: false fire = fired ∧ [bare 同一課題が硬あふれ無し **∧ トークン総量比 < 1.5x**]。反例：bare が 100k で完走した課題で sentinel が不要に発火し分解して 500k（5x）を消費した場合、発火は不要だったのに比が 1.5x 超のため **false fire に分類されない**。つまり定義は「無害な不要発火」だけを数え、最も有害なクラスを除外する。除外方向が sentinel 承認側に偏る（anti-conservative）ため、default-on 可否の主指標として不適格。さらに haiku の合格基準は完遂率のみでトークン条件が無いので、このクラスは**どの凍結済み合格基準にも一切現れない**。
**最小修正**: false fire = fired ∧ bare 硬あふれ無し（必要性の反実仮想のみで定義）とし、1.5x は harmless/harmful false fire の**層別閾値**に格下げして両方の率を報告する。

**B3. sweep 選定規則が codex 発火率0 を制約にするが、sweep に codex セルが無く制約を評価できない（実行不能な凍結規則）**
副腕3 の凍結グリッドは sonnet-5 × p2-M × 1seed の6セルのみ。凍結選定規則は「codex 腕の発火率0 を制約条件とし、その下で sonnet のトークン比を最小化する (T_abs, w) を既定値に採用」。codex の発火率は主グリッド（既定 40k/50%）でしか測定されないため、**既定以外のセルが選ばれた場合その制約は検証不能**（T_abs=30k 低下方向は発火増加方向であり、codex の構造的約束「検索型には発火しない」が未検証のまま既定値になりうる）。事前登録の決定規則として、一部の分岐が実行不能なら凍結の意味をなさない。
**最小修正**: sweep 6セルに codex を追加（+6本・p2-M 単価で概算影響小）、または「codex 検証済みセルに限定できなければ既定値維持で fail-stop」という規則を凍結する。

## Non-blocking findings

1. **slope の計算系列が未指定**（§4）: 生 injected_t 上か MA(injected,3) 上か、および slope の最小fit点数。実装者が任意解釈できるので1文で固定を（EV-007 の較正にも効く）。
2. **細かいスキーマ**: `threshold_hit: abs|ratio` に `both` が無い / tap_status の正常値（ok?）が列挙されていない / task_end に started_at・elapsed が無い（ledger 合流なら join で足りるが、独立ファイルを採る場合の条件に明記を）。
3. **reasoning floor 表が参照のみで未収載**: 実装 Issue に表本体と出所を必ず載せること（unknown=240s 方針は正しい）。
4. **統計粒度**: 主グリッドは腕あたり n=4（2課題×2seed）で、haiku の合格基準マージン（−10pt / +15pt）は1本=25pt の粒度に対して判定がコインフリップになりうる。サブタスク単位の完遂採点を事前登録するか haiku だけ seed 追加を推奨（マージン自体は EV-006 の +30pt 観測由来なので方向は妥当）。
5. **miss の lead-time 定数（3ターン）と 64k 強制副腕の物理的整合**： L帯の heavy injection では overflow が turn 3 前後に来る可能性があり、その場合 miss≈100% が sentinel の遅さと区別できない。miss を lead≥1 と lead≥3 の2本で報告するだけで解消（コスト増なし）。
6. **F6 の Issue 側訂正（Files-to-touch → core）は埋め込み資料から検証不能**。delta 記録で実施済みことを確認されたい。
7. **課題名の表記ゆれ**: 主グリッド p2-M-i1 / 副腕2・3 p2-M。同一課題か別課題かを prereg で明示（seed・シャッフル単位の特定に効く）。

## Model identity

- requested: glm-5.3（GLM 席・r1 と同一席）
- actual: GLM-5.3（Zhipu）— Claude Code wrapper 経由・effort high
- 条件: fresh context / read-only / 埋め込み資料のみ（外部検索・repo 参照なし）・r1 記憶には依存せず同梱の裁定記録のみを使用

総評一句: v0.3 は r1 の指摘をほぼ誠実に落とし込んでおり、残る3件はすべて事前登録書の数行〜十数行修正で解ける。B1〜B3 を潰した v0.4+prereg v0.2 なら次の delta で GO を出せる見込み。
