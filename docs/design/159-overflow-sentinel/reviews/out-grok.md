設計ドラフトと埋め込み証拠を全部読んでから、実装開始を止めるべき点があるかを判定します。まず全文を確認します。設計の方向は D1–D5 に沿っている。ただし実装が始まると、発火条件・閾値の単位・ログラベルが実装者の推測になる穴が残っている。

## Verdict

**NO-GO**

D1–D5 の決裁そのものは正しく実行されている（core 判断 + tap、実測、v1 は提案のみ、既定は上書き可能、default-on 前に EV-007）。実装開始を止める理由は方針のやり直しではなく、**発火観測量・窓比閾値・事後ラベル・TTFB の作用面・EV-007 事前登録**が、このドラフトのままでは一意に実装・較正できないこと。v0.3 で下の MAJOR を閉じれば、同じ骨格で GO を取りうる。

## Blocking findings

1. **MAJOR — §2 tap 契約 vs §3 チェックポイント（D-1 / D-3）**  
   **Why it blocks.** 発火の本体が二系統のまま結合規則がない。§3 は「次リクエスト送信直前」に `次回注入 ≈ 今回注入 + 今回出力 + ツール結果` を測ると言い、Hermes の `estimate_request_context_tokens` と同じ位置だと書く。一方 §2 の tap は `turn: {ts, input_tokens, cache_read_tokens, output_tokens, model, ctx_window}` と `byte: {ts_first_byte}` だけで、列挙されている取得元はすべて **ターン完了後**（claude stream-json per-message usage / codex `turn.completed` / agy stream-json `result`）。ツール結果トークンも pre-send 推定値もない。D1=B の core は CLI の HTTP 送信点にいないので、この観測源のままでは Hermes 位置の判定は物理的にできない。さらに `input_tokens` が cache_read を含むか（Anthropic は排他加算が正、OpenAI 系は `prompt_tokens` が cached を内包しうる → 加算で二重計上）、`cache_creation` を入れるかも未定義。水位（N 移動平均）と送信前点推定が AND なのか OR なのか、1 ターン目（usage なし）を点推定だけで発火させるのかも無い。このまま実装すると「事後 usage の MA」と「送信前推定」の別物が両方 sentinel を名乗る。  
   **Fix.** v1 を **EV-006 と同じ観測量に凍結**する: ターン完了 usage の `injected = input + cache_read [+ cache_creation]` の MA + 傾き。1 ターン遅れは 209 ターン × ~112k のスケールでは無視できる、と明記。`input_tokens` は cache_* を含まない正味、と tap 契約に書く。pre-send は v2: アダプタが任意で `pre_send {estimated_tokens, tool_result_tokens, payload_bytes}` を足し、core は決裁だけ持つ。v1 で pre-send を残すなら、runtime 内フックの可否を claude/codex/agy ごとに書き、無い runtime は post-turn に degrade すると契約する。結合規則は一行でよい: `fire if MA(injected, N) > w·W OR (slope projects hit within M)`（点推定はまだ使わない）。

2. **MAJOR — §4 水位を `ctx_window × w%` にしたこと（D-2 / D-7 / D-8）**  
   **Why it blocks.** EV-006 が示した得は **絶対トークン/ターン**（sonnet L bare ~112k/turn vs harness 20–40k → 4–6x）であり、「窓の何 % まで逼迫したか」ではない。同帯は 200k 窓なら ~56% だが、1M 窓では 11% で、w=50% は **一生発火しない**。§4 の梯子で窓を正しく取ること（HF 262,144、カタログの 1M）は、相対閾値の下では **発火を遅らせる/消す**。保守的 200k 既定だけが偶然 112k を 56% と見て発火する、という逆説になる。§8 は 1M をレビュー質問にしているが v1 ポリシーが無い。w=50% の根拠も ROC ではなく「すでに損が確定していた定常値 ~56%」の近傍であり、較正腕 {40,50,60}% は「harness が効き始める 10–20%（20–40k / 200k）」をsweepしていない。  
   **Fix.** 水位を二本にする: **絶対** `injected > T_abs`（既定案は EV-006 の harness 上界付近、例 40k、config 可）**または** **相対** `injected > w·ctx_window`（あふれ射影用）。1M は相対だけではスコープ外と書かない。v1 を ≤256k に切るならその切る理由と、梯子が正確値を返したときのフォールバックを書く。EV-007 の w sweep に絶対閾値（例 30k/40k/80k）か、相対なら {15,25,40,50}% を入れる。

3. **MAJOR — §5 ログでは誤発火/見逃しを測れない（D-4）**  
   **Why it blocks.** `outcome_followup ∈ {completed, overflowed, decomposed}` は EV-006 の成功定義と一致しない。sonnet L は ~112k/turn で **20/20 完走**しつつ 4–6x 高い。発火 + `completed` を誤発火にすると、得をする本命ケースが全部誤発火になる。v1 は提案のみなので、発火は分解を起こさず、nudge 無視で完走したのか「分解不要だった」のかも区別できない。非発火サマリのフィールドが未定義。JSONL の同一行に追記する更新は欠測・競合に弱い。`ttfb_ms` と `first_byte_at` はあるが `started_at` / どの軸で発火したか / 推定 vs 実測 が無い。§6 の主要エンドポイントが「§5 のログで誤発火/見逃し」と書いてあるので、このラベルのまま EV-007 を走らせると較正が壊れる。  
   **Fix.** イベントを分ける: `fire` と `task_end`（in-place 更新しない）。`task_end` に最終 injected 系列または要約（max/last-N mean）、総トークン、硬あふれ（API 窓エラー）の有無、`nudge_disposition`（accepted/ignored/n/a）、`axis: level|slope|both|alert`、`tap_status`。誤発火/見逃しは文脈で定義する。本番: 硬あふれ・nudge 採用率。EV-007: 対 bare のトークン比と正答の反実仮想（3 腕）。`completed` を真陰性に使わない。

4. **MAJOR — §3-3 / §5 TTFB を overflow sentinel に同居させ fail-loud にしている（D-5）**  
   **Why it blocks.** D3 の v1 は「提案のみ」。TTFB は「ゼロバイトのまま床を超えたら fail-loud（decompose ではなく alert）」で、Hermes 輸入値は watchdog→kill→再接続まで含む。alert がログなのか step 失敗なのか未定義。作用面が閉じない。pattern-4 / CLAUDE_BIN は **文脈過多ではなくクライアント決定論ハング**（リクエスト未送信、0 バイト、1200s 沈黙）。その検出価値は REPORT-pattern4-rootcause と Hermes カタログが支持するが、所属は既に #162（zero-output failure class）側。GLM-5.3 常時 thinking の誤殺（hermes#89241）を overflow 較正に混ぜると、EV-007 のトークン経済とハング検出が交絡する。  
   **Fix.** byte tap は共有してよい。判定とアクションは分ける: overflow sentinel = nudge+ログのみ。TTFB = #162（または別モジュール）。v1 に残すならアクションを **alert-only（kill しない）** と書き、reasoning floor の unknown 方針（GLM 欠載を繰り返さない）を表に入れる。SSE ping を first byte に数えない、と Hermes の教訓を契約に落とす。

5. **MAJOR — §6 はこのまま事前登録できない（D-6 / D-8）**  
   **Why it blocks.** 腕の直積が未凍結（3 実行腕 × 3 モデル × w 3 点 × 分解者 A/B/C）。n・検出力・非劣性マージン・多重比較・除外（DLQ）・乱数単位が無い。sentinel 腕は「v1 + auto-enqueue on の実験特例」なので **本番 v1（nudge）ではなく v2 政策**を測る。一方、bare で N ターン積んだあと `tr-enqueue` する **途中エスカレーション**（既存会話をどうするか、step を止めるか）が §5 に無い。EV-006 は **最初から** harness 分解しており、途中切替の証拠は無い。haiku の主エンドポイントは正答非劣性ではなく完遂率（+30pt）、codex は発火率 0 かつトークンが bare より悪くないこと、sonnet はトークン節約、と仮説がモデルで違うのに一本の「正答非劣性 + トークン」しか無い。Qwen3.8 レポート自身が「claude CLI（全読み込み runtime）に載せてもモデル側で検索型」を D2 の支持例にしているのに、§6 のモデルは sonnet / haiku / codex だけで、その反証ケースが無い。窓ロック（qwen は `CLAUDE_CODE_MAX_CONTEXT_TOKENS=262144`）もプロトコルに入っていない。  
   **Fix.** 事前登録を別節（または別紙）にし、次を freeze する: (i) 主比較の分解者条件は A（リグ固定）1 本。B/C は入れ子で n を別に書く。(ii) モデル別仮説とマージン。(iii) sentinel 腕が auto-enqueue なら **mid-task handoff 契約**（現行 step を abort し、残作業を新 task-runner 計画で再開、等）を §5 に書く。nudge 効果は別測定と明記。(iv) 一般化腕に「検索型モデル × 全読み込み runtime」（qwen on claude CLI）を 1 本。(v) 窓・timeout・shim env をアーム間で固定。(vi) 較正の選び方（例: codex 発火率 0 を制約に、sonnet トークン比を最大化する w/T_abs）。実装は「上書き可能な instrument」までなら、この事前登録の freeze を実装開始条件から外すと明記してよい。外さないなら設計レーン未完。

## Non-blocking findings

- **D-1 失敗モード（仕様に一行ずつ書けば足りる）.** ツール結果の単発スパイクは N=3 MA では落ちるが、pre-send 点推定を残すと検索型の巨大 grep で一発発火する。傾きは定常化後 ~0（sonnet はあふれせず 112k で高原）なので、v1 の本命は水位で、傾きは立ち上がり専用と書く。非単調（圧縮は v1 非目標、§7）は見逃しモードとして明示。  
- **D-2 既定の論理.** n=1 pilot 由来を「上書き可能な prior、default-on は EV-007 後」とする枠は D4/D5 に合う。弱いのは w の位置（高い定常値の近傍）と N/M を sweep しないこと。M=10 は残タスク量なしの代用として v1 では許容。  
- **モデル class prior（§4）.** D2 は prior を許す。ただし search を「実質オフ」にすると、Qwen（runtime は all-load、挙動は search）のラベル先が runtime かモデルかで逆の答えになる。既定は `unknown = 実測のみ`、search prior は明示オプトインが安全。  
- **D-3 degrade.** tap 無し → sentinel 無効は v1 では無害。ただし「発火しなかった」と「見えていない」が区別できない。`tap_status` を非発火サマリに入れる。`ctx_window` を turn イベントでアダプタが送ると §4 梯子と衝突する。アダプタは runtime 申告を optional で付け、梯子は core が適用する。スキーマ版も無い。Issue の Files to touch が `adapters/claude-code/` に sentinel 本体を置いており、D1=B と食い違う（実装予測の更新漏れ）。  
- **D-4 追加フィールド.** Hermes `stream_diag` 由来の HTTP status / 推定リクエストサイズは CLAUDE_BIN 再発の事後解剖に有用だが v1 必須ではない。`first_byte_at` を fire と attempt receipt の両方に必須化する判断は pattern-4 と整合。  
- **D-5 同居の是非.** 実装効率と「沈黙ハングを窓あふれと誤認しない」教育効果はある。それでも作用面が nudge vs fail-loud で違うので、共有するのは byte tap だけにすべき。  
- **D-7 梯子の細部.** config > HF config.json > カタログ > 200k は qwen 24% 過小（実窓 262,144）と glm 200k 仮定の実例に合う。壊れるのは (a) 1M（相対閾値、上述）、(b) 128k モデルへ 200k 既定 → 閾値が高すぎて見逃し、(c) `max_position_embeddings` ≠ 提供窓（Qwen 公式評価は 256K）、(d) HF を offline で取れないときの fall-through 未記載。  
- **D-8 EV-006 が支持していないもの.** 中タスク切替 ≒ 最初から harness、線形射影があふれを当てる（実測は高原）、検索型は構造上トリップ（Qwen×claude CLI は反例候補）、TTFB 床表の穴なし輸入（GLM 欠載）。再走後の glm/muse は「第4パターン撤回」を支持するが、qwen 再走は当該レポート時点で実行中。  
- **ログ置き場（§8）.** 別ファイル `sentinel-fire.jsonl` より task-runner ledger に同 `task_id` で流した方が followup 結合が壊れない。理由を「sentinel を ledger 実装より先に単体計測したい」と書くなら許容。  
- **較正腕.** w だけ振ると T_abs / N / M の誤りを吸収できない。小規模なら T_abs を優先（EV-006 の可観測と一致）。

## Model identity

Grok 4.6（xAI）。この席は埋め込み資料のみの read-only レビュー。コード・コマンド・外部参照は使っていない。
