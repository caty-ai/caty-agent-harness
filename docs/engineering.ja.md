# Caty Agent Harness — エンジニア向けドキュメント

[English](engineering.md) | [日本語](engineering.ja.md) ｜ [玄関ページへ戻る](../README.ja.md)

エンジニア向けの技術ガイドです。何が・どこで・どの強さで実際に強制されるのかを説明します。コマンドフラグと契約文書の正確な一覧は[詳細仕様](reference.ja.md)にあります。

---

## AI へのお願いではなく、AI の外側の仕組み

AI に「全部覚えて」「諦めないで」と頼んでも、それは 1 回の会話の中のお願いです。AI が実際に作業するプロジェクトのフォルダを **workspace** と呼びます。Caty Agent Harness はその作業フォルダで、会話の外側からファイルと確認によって仕事を管理します。

`scripts/task-runner.sh` は、1 つの仕事を記録付きの手順に分け、完了したかを確かめるスクリプトです。このスクリプトが管理する仕事だけに、完全な完走レールが適用されます。ほかの登録済み自動経路は、新しい仕事を止める一時停止の門番（pause barrier）や定期確認・停止や異常の監視（watchdog）のような、それぞれの狭い契約だけを守り、完走レール全体を適用するものではありません。Claude Code、Codex、Kimi の通常の対話作業では、作業開始時の短い指示（managed bootstrap）と作業終了時の確認（`Stop` hook、Claude Code は会話圧縮前の確認 `PreCompact` hook も）の範囲で働くため、すべてを同じ強さで強制するものではありません。

すべての対応経路で共有する仕事の記録は、次のとおりです。

- 引き継ぎノート（`STATE.md`）に、今わかっていること、過去の失敗、再開点を残す。
- 実行記録と成果物を残し、次のやり取りに具体的な再開点を渡す。

完全な完走レールでは、`task-runner` がさらに次を強制します。

- 状態メッセージを信じるのではなく、頼んだ結果を実際に確認する完了チェックを動かす。
- 試行回数と作業時間の上限を置き、進まない努力をいつまでも続けない。
- 次の試行には前の失敗を渡し、生成される step prompt を通じて別の回復方法を取るよう指示する。機械的に強制されるのは失敗情報の注入と次項の停止則である。
- 同じエラー class の反復や進捗なしを検知したら、無限に消耗せず止める。

だから AI を替えたり新しいやり取りを始めたりしても役立ちます。大事な仕事の記録を、AI との会話だけでなく作業フォルダに残すからです。

---

<a id="learning"></a>

## 繰り返す失敗から学ぶ

**完走レール**とは、`scripts/task-runner.sh` が管理する仕事のことです。長い仕事を正直な完了へ運ぶため、記録された道筋を用意します。通常の対話作業とは異なり、指示や確認だけで全手順を強制するものではありません。

### 1 つの仕事の中：完走レール

1. 失敗理由と、それを示した証拠を記録する。
2. 次の試行ではその失敗を渡し、同じ再試行ではなく別の回復方法を求める。
3. エラーが反復する、または仕事が進まないときは、無駄に続けず止める。

### 別の仕事へ：確認済みの学びだけを持ち越す

1. 完了確認に通った方法は、まず教訓として残せる。
2. 教訓を再利用できる手引きや確かな情報にするのは、別々の 2 つの仕事で、同じ教訓がそれぞれ独立した検証（完了確認）に通った場合、または人が明示的に昇格させた場合だけにする。
3. 次の似た仕事では、確認済みの記録を参照してから始める。

これにより失敗の反復を減らし、検証済みの解決策を再利用します。「二度と失敗しない」「必ず成功する」という意味ではありません。

### ループの 6 段階

玄関ページでは 1 枚の図で示している流れを、設計文書での名前で示します。

1. **CONSULT** で引き継ぎノート（`STATE.md`）と関係する確認済みの教訓を読む。
2. **PLAN** で、作業前に何を証拠として完了とするかを書き出す。
3. **ACT** で結果を作り、それを支える証拠も残す。
4. **CHECK**（設計文書では **VERIFY**）で、まず機械的な完了確認を動かす。独立した確認は設定された場合だけ使うが、設定されていない場合も機械的な確認が中心。確認サービス（provider）が使えないときは、自己確認に置き換えず、昇格を保留する。
5. **REPAIR / LEARN** で失敗記録を使って直すか、確認済みの教訓を残す。証拠に基づいて教訓を整理することを、設計文書では **DISTILL** と呼ぶ。
6. **CHECKPOINT** で、次のやり取りに信頼できる再開点を渡す。

---

## 5 つの AI ツールで強くなること

Harness は各ツールが支えられる範囲で同じように役立ちます。

| AI ツール | 利用者にとって楽になること |
| --- | --- |
| Claude Code | 作業の区切り、会話の圧縮、文脈の切断をまたいで、引き継ぎノートと完了の確認を残せる。 |
| Codex CLI | 作業の区切りをまたいで、引き継ぎノートと完了の確認を残せる。 |
| Kimi Code CLI | 作業の区切りをまたいで、引き継ぎノートと完了の確認を残せる。 |
| Hermes Agent | さらに、1 手順ずつ決めた時刻に進める仕組み、完了確認、やり直し、停止や異常の監視を使える。 |
| OpenClaw | 結果から役立つ学びをまとめて記録し（distillation）、定期的に見守る（sentinel）道筋を使える。 |

実装範囲は意図的に非対称です。Harness はすべてのツールに同じ native 機能があるとは主張せず、存在しない機能を捏造しません。

---

<a id="quickstart"></a>

## クイックスタート（完全版）

> AI エージェント経由で導入する場合は [agent-guide.md](agent-guide.md)（英語）を渡してください。runtime の選択・ヘルスチェック・必要な後続配線まで一本道で案内します。

installer、scaffold、pause command の前提は、Git と bash 3.2+ が動く macOS、Linux、または [WSL2 サポートメモ](wsl2-support.md)の条件を満たす WSL2（Ubuntu on Windows）を使っていることです。native Windows は非対応です。runtime hook、`task-runner`、adapter integration、fully operational な runtime 配線には Python 3 が必要です。

```sh
git clone https://github.com/caty-ai/caty-agent-harness.git
cd caty-agent-harness
WORKSPACE="$HOME/your-agent-workspace"
./install.sh --workspace "$WORKSPACE" --bootstrap-runtime codex --append-bootstrap "$WORKSPACE/AGENTS.md"
./install.sh --check --workspace "$WORKSPACE"
```

`codex` と `AGENTS.md` は例です。`WORKSPACE` には、AI が実際に作業する既存のプロジェクトのフォルダ、または新しく作るフォルダを**絶対パスで**指定してください（`--append-bootstrap` の対象は絶対パス必須で、親ディレクトリが実在し symlink でないこと）。実行環境と指示ファイルは、[agent-guide.md](agent-guide.md#step-1--identify-your-runtime) の対応表か、対応する adapter `INSTALL.md` から選びます。指定した作業フォルダや対象の指示ファイルがまだなければ、このコマンドが作成します。初期化は足りない構造（scaffold）だけを作ります。

`--check` は read-only です。必須 layout が健全なら、最後に次を表示します。

```text
ok: required layout and STATE.md headers present
```

verifier availability や cron wiring など、optional learning-path row も表示します。required layout と required `STATE.md` header が健全でも optional row に `FAIL` が出ることがあります。この場合の exit code は `0` です。ただし `FAIL` は、その runtime で loop が fully operational ではないことを示します。利用前に対応する adapter の配線を完了してください。フラグの全一覧は[詳細仕様](reference.ja.md)へ。

**クイックスタートは導入の全部ではありません。** ここで作られるのは workspace の scaffold と managed bootstrap までです。作業終了時の checkpoint リマインダーや深い自動化には、次節の runtime 別配線（ユーザー階層の hook / cron 登録）が必要で、それまでは bootstrap block による作業開始時の規律だけが有効です。

---

<a id="runtime-setup"></a>

## runtime 別設定

クイックスタートの後、選んだ runtime の integration を完了してください。

| Runtime | 設定文書 | 実装済みの Harness 範囲 |
| --- | --- | --- |
| Claude Code | [adapters/claude-code/INSTALL.md](../adapters/claude-code/INSTALL.md) | managed bootstrap、pause-aware `Stop` / `PreCompact` hook entry point |
| Codex CLI | [adapters/codex/INSTALL.md](../adapters/codex/INSTALL.md) | managed bootstrap、pause-aware `Stop` hook entry point |
| Kimi Code CLI | [adapters/kimi/INSTALL.md](../adapters/kimi/INSTALL.md) | managed bootstrap、pause-aware `Stop` hook entry point |
| Hermes Agent | [adapters/hermes/INSTALL.md](../adapters/hermes/INSTALL.md) | managed bootstrap、verifier route、task-runner step、cron/watchdog path |
| OpenClaw | [adapters/openclaw/INSTALL.md](../adapters/openclaw/INSTALL.md) | managed bootstrap、distillation、sentinel cron path |

この表は意図的に非対称で、すべての runtime に同一の native 機能があるとは主張しません。

### Flush intake consumer

上の Claude Code の `Stop` / `PreCompact` hook は producer に過ぎません。その産物は `loop/pending/flush-*.md` の未検証の記録です。どちらかの producer を有効にした workspace は、consumer である `adapters/claude-code/flush-intake.sh` の定期実行も必ず設定してください。さもないと、その記録は governed な `STATE.md` の fold に届かないまま溜まり続けます。同じ deterministic な consumer は、Codex CLI と Kimi Code CLI の workspace でも使えます。両者の checkpoint hook が同じ flush format を出力するためです。

consumer は 1 日 2〜4 回実行してください。LaunchAgent なら `StartInterval` を `21600`〜`43200` 秒にします。毎日 1 回の schedule では、既定の deadman threshold に対して jitter の余裕がありません。consumer は model を呼ばないため、scheduler に Claude の credential は不要です。それでも macOS の scheduler surface としては `gui/<uid>` domain の LaunchAgent を推奨します。claude CLI を叩く tick wrapper や spawn adapter はいずれも LaunchAgent が必須です。crontab session は user Keychain に到達できないためです。Linux/WSL2 ではこの Keychain の根拠は当てはまりません。cron（`0 */8 * * *` 形式）か systemd user timer（`OnUnitActiveSec`）が同じ役割を果たします。cron が自動起動しない WSL2 の罠と、user-local な CLI インストール向けの wrapper `CATY_WRAPPER_EXTRA_PATH` override は [WSL2 サポートメモ](wsl2-support.md#scheduling-on-linuxwsl2)を参照してください。

fold 経路は workspace につき 1 本だけです。この consumer か、OpenClaw の `distill-audit.sh` のどちらかを使い、両方の併用はできません。consumer 自身は、共有 STATE lock を取得し、infrastructure error なく完了した後にだけ `loop/.deadman/distill.marker` を touch します（self-marking 設計）。チェックイン済みの cron wrapper（`templates/cron-wrapper.tmpl.sh`）はまさにこの consumer を self-marking として認識し、`DEADMAN_MARKER` がその workspace の `distill.marker` を指す場合は自身の pre-touch を抑制します。したがって明示的に設定しても lock starvation や intake failure が隠れることはありません。`DEADMAN_MARKER` を未設定のままにするのは、wrapper が識別できない proxy や rename された対象の場合です。

詳しいセットアップ手順・ledger の形式・schedule の詳細は [adapters/claude-code/INSTALL.md](../adapters/claude-code/INSTALL.md) を参照してください。

### Overflow sentinel

Claude Code の step adapter は、passive な overflow sentinel を opt-in で利用できます。
sentinel は Claude の `stream-json` を tail し、assistant message を identity で dedup した上で、
各 prompt を input・cache-read・cache-creation token の排他的な合計として測定します。
shadow mode は判断を記録するだけで、active mode は次の task-runner step へ渡す 5 点の delta nudge も
準備します。model を中断・signal することはなく、model 終了後の bounded な記録確定 join を除いて
model を block しません。

sentinel は healthy tap、cache accounting 不足、tap absent、全ゼロの blind tap を区別します。
runtime host が compaction を所有する場合は `OVF_COMPACTION_OWNER=host` を設定します。この場合は
水位述語を実行せず `disabled-host` を記録します。有効時に owner を未設定のままにすると warning を出し、
sentinel heuristic を選びます。

Claude の明示的な `system/compact_boundary` event を観測すると measured series を reset します。
この event が得られない場合は injected-token の急落 heuristic が fallback のままです。

task 途中で model や runtime が切り替わった場合は、regime を混ぜずに計測をリセットします:
移動平均・傾き履歴・nudge hysteresis が再スタートし、model-keyed な閾値がすべて再解決されます —
per-model 閾値表（`OVF_MODEL_THRESHOLDS`）もここに含まれ、表は空で出荷されるため、較正済みの
per-model 値は後からコード変更なしの純粋な設定として投入できます。sentinel は自分の計器（tap）も
監査します: turn ごとの生 usage を一定周期で正規化ルールに再適用し、数値が食い違う場合や regime 途中で
usage schema が変わった場合に `tap_drift` event を記録します — 「発火しなかった」「見えていなかった」と
並ぶ、記録のみの第 3 の計器状態（「計器が嘘をついた」）です。

監視対象の各 attempt は `turn`、`fire`、`alert`、`regime_change`、`tap_drift`、`attempt_end` を独立した
`sentinel-events.jsonl` へ append します。task-runner ledger に confluence point ができるまでは
このファイルを分離して保持します。次 step 境界で nudge を配送するため、発火した attempt で task が
終了すると pending nudge を受け取る runtime がない、という既知の制限があります。`suppressed` の
fire/terminal disposition により、この未配送は計測可能です。passive な `claude -p` stream からは
run start と最初の assistant byte しか観測できず、request ごとの境界は観測できないため、inter-turn
TTFB stall も後続版へ延期します。

---

<a id="pause"></a>

## workspace を pause する

pause は作業フォルダ（workspace）単位で元に戻せる一時停止です。完全な取り外しではありません。

```sh
./install.sh --disable --workspace "$WORKSPACE" --dry-run
./install.sh --disable --workspace "$WORKSPACE"
./install.sh --check --workspace "$WORKSPACE"
./install.sh --enable --workspace "$WORKSPACE" --dry-run
./install.sh --enable --workspace "$WORKSPACE"
```

一時停止の印（pause marker）を置いても、`STATE.md`、確認済みの手順、保留中の仕事、待ち行列、VERIFY の履歴、仕事の状態、成果物は保持されます。PC 全体の hook、実行環境の設定、定期実行（cron）は残ります。登録済みの一時停止対応の Harness 実行入口は、選んだ作業フォルダで動かなくなります。ただし、以前にコピーした定期実行用の wrapper など古い配線は、adapter 文書に従って更新が必要な場合があります。`--check` の警告に従ってください。初期化、指示の追記（bootstrap append）、wrapper の確認（attestation）、`scripts/family-updater` など、明示的な初期設定・制御・更新 command は、一時停止中も使えます。一時停止は次の実行入口から有効で、すでに進行中の処理を止めません。

| 境界 | pause 中の動作 |
| --- | --- |
| 登録済みの一時停止対応の実行環境 hook、定期実行、AI 呼び出し経路、仕事の開始・進行の入口 | hard pause: 選んだ作業フォルダで新しい Harness 作業を始めない |
| 作業開始時の指示（managed bootstrap instruction） | soft pause: AI に Harness の指示を飛ばすよう伝える。AI の遵守に依存する |

`--check` は、一時停止中に対話作業の開始時指示がどこまで効くかを表示します。状態の正確な値は[詳細仕様](reference.ja.md#pause-states)へ。

これは意図的に完全な取り外しを約束するものではありません。PC 全体で使うものを安全に取り外すには、管理記録（managed-resource receipt）が必要で、現行機能の範囲外です。

---

<a id="completion"></a>

## 技術的な実装範囲

`STATE.md` は小さく上限のある operational-memory file です。session をまたいで残る task pointer、verified fact、rule、open failure を持ちます。weight training、自己改造、model 自体を変えるものではありません。

通常の interactive 作業では、managed instruction file が task start に `STATE.md` を読むようエージェントへ促します。通常の interactive prompt ごとに、Harness が全文を injection するわけではありません。`scripts/task-runner.sh` は意図的な例外で、schedule された fresh-context step が workspace の operational context を受け取れるよう、生成する step prompt に `STATE.md` を injection します。

`task-runner` は弱い agent のための completion scaffold です。agent の知能そのものを魔法のように上げるものではありません。rubric テンプレート（`loop/RUBRIC.tmpl.md` を scaffold する。rubric の*採点*は後続バージョン送り）、explicit step budget、retry、no-progress stop、実行可能な `donecheck`、設定・配線されている場合の independent verifier、証拠を残す DLQ により、途中脱落、同じ失敗の繰り返し、根拠のない完了を減らします。

各 scheduled tick は fresh-context の 1 step だけを実行します。task ごとの file が attempt state、receipt、artifact、`delivered/`、`dlq/` を保持するため、進捗は 1 回の長い session に依存しません。

Claude Code、Codex CLI、Kimi Code CLI にはそれぞれ generation / execution の能力があります。Hermes Agent と OpenClaw には native の memory / skill-evolution mechanism もあります。Caty Agent Harness はそれらの横に置かれ、evidence-bounded operational memory、verification、completion discipline を足します。native learning を置き換えず、すべての runtime に同じ native mechanism があるとも主張しません。

---

## 縦軸・横軸

Caty Agent Harness は、maintainer たちのマルチエージェント環境 Family OS の縦軸です。個々の agent が仕事をまたいで学び、複数 step の仕事を完走する力を強くします。Family Memory Architecture（FMA）は横軸で、複数 agent 間の memory、schedule、provenance をつなぎます。役割は直交しており、競合しません。両プロジェクトは公開済みです。[Family OS](https://github.com/caty-ai/family-os) と [Family Memory Architecture](https://github.com/caty-ai/family-memory-architecture) を参照してください。

---

## ディレクトリ地図

リポジトリのどこに何があるか、workspace に何が作られるか。

```text
caty-agent-harness/
├── install.sh              # 正規 installer: scaffold・bootstrap 追記・check・pause
├── scripts/                # task-runner, loop-init, tr-enqueue, family-updater, pause lib,
│                           # watchdog/deadman probe, wrapper attestation
├── adapters/               # runtime 別配線（claude-code / codex / kimi / hermes / openclaw）:
│                           # INSTALL.md, bootstrap-block.md, hook, verifier/cron script
├── templates/              # step-prompt, rubric, cron-wrapper, task テンプレート
├── tests/                  # 契約を固定する全 shell suite
└── docs/                   # 本ガイド, reference, agent-guide, plugin/governance 文書
    └── design/             # 内部設計メモ
        ├── DESIGN.md               # learning-loop 契約（正本）
        └── DESIGN-task-runner.md   # task-runner 契約（正本）

<workspace>/                # install が作る、あなたのプロジェクトフォルダ
├── STATE.md                # 引き継ぎノート（bounded operational memory）
├── skills/  skills/_staging/
├── loop/                   # RUBRIC.tmpl.md, pending/, artifacts/, VERIFY.log.md
└── <指示ファイル>           # CLAUDE.md / AGENTS.md / …（印つきブロックを追記）
```

---

## アーキテクチャ

設計原則は **daemon、database、central controller を増やさず、plain file、scheduler tick、receipt、atomic state transition で作る** ことです。

| Component | 役割 |
| --- | --- |
| `STATE.md`、`skills/`、`loop/` | workspace の bounded operational memory、promoted skill、work evidence |
| `install.sh` / `scripts/loop-init` | idempotent な missing-scaffold 初期化、managed bootstrap、health check、reversible workspace pause |
| `scripts/task-runner.sh` | task ごとの state と executable completion check に支えられた、tick ごと 1 fresh-context step |
| `scripts/tr-enqueue` | task file を検証して enqueue し、pause 中は新しい queue write を拒否する |
| `adapters/*` | runtime ごとの hook、verifier route、schedule wiring |
| [plugin-convention.md](plugin-convention.md) | 許可された plugin seam と extraction policy |

`ops-reliability` は、この repository に物理的に同居する logical capability です。別 repository や central controller ではありません。retry classification、watchdog / deadman path、wrapper conformance、updater / rollback receipt を担います。

plugin は `tr-enqueue`、pinned template、read-only artifact consumption を通じて接続します。task state への直接 authority は得ません。

---

## 境界マップ

このプロジェクトが所有するもの・意図的に所有しないもの。

| System | 現在の役割 | 所有しないもの |
| --- | --- | --- |
| Caty Agent Harness | 個々の agent の operational memory、verification discipline、task completion | agent 横断の memory 連携や policy の authority |
| `ops-reliability`（同居） | install/check/pause、watchdog、updater、rollback、receipt mechanism | domain success semantics、central controller |
| `self-growth-loop`（private plugin） | Harness 結果を read-only で使う proposal/governance/adoption workflow | task semantics、task-state の直接 write |
| `persona-growth-loop`（private plugin） | planned vocabulary/persona proposal plugin | scheduler、ledger、adoption authority |
| `sitter`（[caty-ai/sitter](https://github.com/caty-ai/sitter)） | architecture map の optional supervision seam | この Harness release の integrated default |

---

## ステータス

- ここは Caty AI の public release repository です。開発は private の作業リポジトリで行い、リリースはクリーンなスナップショットとしてここに置かれます。
- canonical installer は pure-shell の `install.sh` です。npm package は提供しておらず、不要です。
- 検証: merge は `tests/*.test.sh` 全 suite の pass を条件にしています。[CONTRIBUTING.md](../CONTRIBUTING.md) の手順でローカル再実行できます。公開 CI も稼働中です。[README の live バッジ](../README.md#project-status)と [`.github/workflows/`](../.github/workflows/) 配下の workflow 定義を参照してください。
- `self-growth-loop` は active plugin consumer、`persona-growth-loop` は planned/scaffolded のままです。
- `sitter` は proposed architecture edge であり、integrated default ではありません。

---

## コントリビュートとテスト

変更提案の流れ・issue-first のルール・コードスタイルは [CONTRIBUTING.md](../CONTRIBUTING.md)（英語）へ。現在の checkout の repository root で、canonical target を通して全 shell suite を実行します。

```sh
make test
```

正確な契約・budget・promotion rule は[詳細仕様](reference.ja.md)に定義があります。
