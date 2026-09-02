# Caty Agent Harness — 詳細仕様

[English](reference.md) | [日本語](reference.ja.md) ｜ [玄関ページへ戻る](../README.ja.md) ｜ [エンジニア向けドキュメント](engineering.ja.md)

フラグ・状態・契約文書の正確な一覧です。このページと設計文書の記述が食い違う場合は、設計文書が正です。

---

## install.sh コマンドリファレンス

```text
./install.sh [--workspace <dir>]
./install.sh --hermes <profile> [--append-bootstrap <file>]
./install.sh --openclaw <workspace-dir> [--append-bootstrap <file>]
./install.sh [--workspace <dir>] --bootstrap-runtime <runtime> --append-bootstrap <file>
./install.sh --check [--workspace <dir>]
./install.sh --disable --workspace <dir> [--dry-run]
./install.sh --enable --workspace <dir> [--dry-run]
./install.sh --help
```

| Mode | 動作 |
| --- | --- |
| 引数なし | `scripts/loop-init --workspace "$PWD"` でカレントディレクトリを初期化 |
| `--workspace <dir>` | `<dir>` を初期化。足りない scaffold だけを作り、既存ファイルは置き換えない |
| `--hermes <profile>` | `$HOME/.hermes/profiles/<profile>/workspace` を初期化し、Hermes bootstrap block と残りの手動配線手順を表示 |
| `--openclaw <workspace-dir>` | workspace を初期化し、OpenClaw bootstrap block、cron template、`STAGING_DIR` 移設メモを表示 |
| `--append-bootstrap <file>` | 選択された bootstrap block を冪等に追記。marker が既にあれば `skip: bootstrap already present` と表示 |
| `--bootstrap-runtime <claude-code\|codex\|kimi\|hermes\|openclaw>` | `--append-bootstrap` が使う marker-aware block を選択。generic mode の `openclaw` は legacy 互換の既定 |
| `--check [--workspace <dir>]` | read-only health check。required layout・`STATE.md` header・pause-control path safety が不正なら exit `1` |
| `--disable --workspace <dir> [--dry-run]` | 元に戻せる workspace pause。`STATE.md`・学習記録・待ち行列・verification history・skill・artifact を保持 |
| `--enable --workspace <dir> [--dry-run]` | pause を解除。harness 所有の通常 `DISABLED` marker だけを削除し、悪意ある marker object は決して辿らない |

追記される bootstrap block の冪等 marker は、リテラル行 `# caty-agent-harness bootstrap v2` です（機械用の marker であり、プロダクト名を変更しても rename しません）。
workspace 初期化時には `loop/.tr-interpreters` も作成されます。これは donecheck の
validation と execution の両方で使う Bash / Perl の絶対パスを記録した2行のファイルです。
既存 workspace では最初の enqueue または runner 実行時に自己修復し、不正な記録は fail closed になります。

---

## --check の意味論

- required layout が健全なら、最後に `ok: required layout and STATE.md headers present` を表示します。
- exit code: `0`＝required layout 健全（optional 行の FAIL はあり得る）／`1`＝required layout・`STATE.md` header・pause-control path safety の不正／`2`＝usage エラーまたは危険 object の拒否。
- optional learning-path row（verifier availability、cron wiring、wrapper conformance）は、exit code が `0` のままでも `FAIL` になりえます。`FAIL` の行は、その runtime の loop がまだ fully operational ではない印です。
- learning-path conformance row は、設定済みの wrapper・probe・provider・evidence file を実行せずに読み取り、hash で確認します。
- adapter author は `SKILL_DESC_MAX`（bytes）を、実測した CONSULT loader budget に設定してください。

<a id="pause-states"></a>

## --check が報告する pause 状態

| State | 意味 |
| --- | --- |
| `paused` | 登録済みの開始時指示がすべて現在の形式で、一時停止に対応している |
| `paused-partial-legacy-bootstrap` | 古い開始時指示が残る。現在の形式で登録済みの自動入口は hard pause だが、古い指示への適用は部分的 |
| `paused-soft-unknown` | 開始時指示の登録記録が揃っていない。対話作業で完全に一時停止できるとは言えない |

---

## Flush intake consumer の receipt

flush intake consumer の会計 ledger は `loop/pending/intake-runs.log` です。deadman の `distill` marker が証明するのは intake が実行されたことだけです。内容レベルの沈黙・dedup・deferral・eviction・quarantine の各件数は ledger で確認します。`loop/archive/` の raw 層は append-only で、自動で prune されることはありません。厳密な所属条件は [DESIGN.md §3.1](design/DESIGN.md#31-files-per-agent-workspace) を参照してください。ledger の詳しい形式と schedule は [adapters/claude-code/INSTALL.md](../adapters/claude-code/INSTALL.md) を参照してください。

## Raw 層のクロスモデルレビュー

```text
scripts/raw-review.sh --workspace <path> [--week <YYYY-Www>] [--dry-run]
```

`--week` なしでは、現在の UTC ISO 週から設定された週数ぶんの raw file 全文と、
前回の正常な nightly snapshot 後に遅着した file を review します。`--week` は指定週で
終わる遡及 window、`--dry-run` は同じ prompt の構築・byte count・file 一覧だけを行い、
reviewer call と遅着 watermark 更新を行わず、notification の書き込み・送信もしません。
exit `0` は検証済み実行、
`NO_GROUPS`、または pause skip、`1` は review 試行後の fail-closed、`2` は usage/config
により review を開始できなかったことを示します。workspace を特定できる全 exit path は
`loop/promotions/runs.log` に receipt を残します。receipt の `error=` は `none` /
`skipped-paused` / `lock-busy` / `chain-exhausted` / `config` / `prompt-too-large` /
`source-normalization`（citation 検証用の raw file 正規化に失敗。chain 系と同じく
fail-closed）のいずれかです。
THEME block 間の空行は許容しますが、block 内の空行は不正です。各 member citation は
比較時に先頭の indentation、1 個の bullet marker、ISO date prefix、`[session-806]` /
`[2026-07-20]` のように内部 whitespace を含まず、ASCII digit または `-` を少なくとも 1 つ含み、
閉じ `]` の直後に space または tab が続く保守的な machine tag、`**bold**` / word-adjacent な
`*bold*` のような paired emphasis marker を除いたうえで、正規化後 8〜200 文字で、
正規化済み source line の先頭に一致する必要があります。
`[IMPORTANT]` / `[NEVER]` のような human warning tag と、意味を持つ lone/glob `*` token は保持されます。
短すぎる citation、行途中だけの一致、fabrication は block 全体を reject します。fabricated block 数が
`max(fabricated_floor, ceil(block 数の fabricated_pct%))` に達すると reviewer call 全体を fail にします。
`fabricated_pct` の既定値は 50、許容範囲は 1〜100 です。`loop/review.conf` の数値は 10 進として解釈するため、
`08` と `0100` は 8 と 100 を意味します。

promotion recurrence の既定は `recurrence_unit=sessions`、`promote_min_k=2` です。
検証済み member は、それを囲む flush header の `session=` 値ごとに数え、同じ session の
複数 member は 1 回だけ数えます。intake-eviction block は session を持たないため、source file と
block index を key にした pseudo-session を各 block に割り当てます。旧形式の headerless block も
同じ fallback を使います。task-runner rig では、fresh-context の各 step は別 session です。
以前の release と同様に `run-k` を異なる ISO 週の数にするには `recurrence_unit=weeks` を指定します。
`promote_min_weeks` の既定は `0`（calendar requirement なし）で、正の値なら recurrence unit に
かかわらず、`promote_min_k` に加えてその数の異なる ISO 週を必須にします。`promote_min_k` は 1 以上、
`promote_min_weeks` は 0 以上の整数でなければなりません。

candidate file は apply consumer との互換性のため、既存の `run-weeks` / `run-k` / `weeks` field を
維持します。apply は sessions mode では範囲検証済みの host-emitted `run-k`、weeks mode では
独自に数え直した distinct `weeks` を使い、さらに `promote_min_weeks` を独立して強制します。
append-only の promotions ledger は情報用の `run-sessions` を記録し、raw-review の run receipt は
設定済み `unit` を記録します。

reviewer route には約 30 個の THEME block を返せる output token 数を設定してください。
claude CLI で wrap した chain では `CLAUDE_CODE_MAX_OUTPUT_TOKENS` も十分な値にします。
output cap に達した route が fence 外の `API Error: ...` 1 行だけを出すと、その call は
grammar 不正として fail-closed になります。修正対象は harness ではなく route 設定です。

同梱の `loop/review.conf` は全行 comment のため情報表示だけの未配線状態です。
`review-config` warning は部分配線または不正な設定だけに使います。`producer=` と `reviewer` を
uncomment する操作は、schedule 実行ごとに選択された raw lesson file **全文**を、その
reviewer に設定した provider（例の reviewer 名は GLM）へ送信する明示的 consent です。
declared producer と reviewer は異なる必要があります。nightly invocation は任意の
runtime-neutral scheduler に登録してください。macOS で reviewer command が `claude` を
呼ぶ場合は LaunchAgent が必須です。Claude CLI の Keychain access を必要としない chain
だけが cron を安全に利用できます。

任意の `notify_cmd` は shell eval されない argv で、設定済み固定引数より先の `$1` として
追記済み notification file path を受け取ります。`install.sh --check` は部分配線・不正設定の
`review-config`、未消費の
review notification、48時間を超える沈黙、設定 threshold 以上の zero-candidate streak を
報告します。

## Promotion apply consumer

```text
scripts/apply-promotions.sh --workspace <path> [--auto-capability-facts]
  [--approve <theme-id>]... [--approve-file <manifest>]...
scripts/apply-promotions.sh --workspace <path> --rollback <theme-id> --reason <ref>
```

consumer は `loop/review.conf` の `recurrence_unit` / `promote_min_k` /
`promote_min_weeks` を raw-review と同じ既定値・validation で読みます。sessions mode の
`run-k` は ASCII の非負整数で member 数以下でなければならず、違反 block は `hygiene` です。
weeks mode では従来どおり apply 自身が distinct week 数を数え直します。recurrence 不足は
既存の terminal token `k-below-2`、calendar spread 不足は `weeks-below-min` です。不正設定は
exit 2 で fail closed し、`apply.log` に `reason=config` summary を残します。theme ごとの
decision receipt と durable provenance は effective `k` と `unit` を記録します。

consumer は anchored な `candidates-<UTC-runid>-<pid>.md` のみを受理し、`.rejects.md` は
読みません。bare run は `STATE.md` を変更せず pending decision を報告し、draft skill stub を
作ります。named fact/rule は explicit approval で、capability-fact は
`--auto-capability-facts` で別枠の上限内に限り promote できます。`apply-index.tsv` が
idempotency authority、append-only の `apply.log` が run-start / transition / summary receipt です。

## task-runner の実行境界

- task frontmatter の `receipt:` は
  `^out/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$` に一致し、`.` と `..` の segment を
  含んではいけません。delivery にはさらに、その target が symlink ではない non-empty な
  regular file で、解決後も task artifact 自身の symlink ではない `out/` 配下にあることが必要です。
- donecheck fence は column zero から始めます。heredoc 内の column-zero fence も文字列として
  extraction を終了させるため、使用禁止です。
- donecheck に渡るのは `TASK_ID`、`TASK_FILE`、`ARTIFACT_DIR`、`TR_DC_CWD`、固定の
  `PATH=/usr/bin:/bin:/usr/sbin:/sbin`、runner 側で set 済みの
  `HOME`/`LANG`/`LC_ALL`/`TZ`、および shell が作る変数だけです。`python3`（3.9+）などの tool は
  この固定 `PATH` から到達できるか、donecheck 内で絶対パス指定する必要があります。
  同梱の `templates/examples/img-pilot.task.md` の donecheck はこの `PATH` 内の `python3` に
  依存します。macOS には `/usr/bin/python3` がありますが、Linux distribution にはない場合が
  あります。それ以外の継承変数は消え、依存していた check は次回実行時に明示的に失敗します。
- `TR_SPAWN_STEP`、`HERMES_STEP_CMD`、`HERMES_PROBE_CMD`、`TR_PUSH_CMD` は shell を介さず
  argv として直接実行されます。`TR_SPAWN_STEP` は引き続き 1 個の絶対 argv word で、かつ
  実行可能な通常ファイルへの絶対パスである必要があるため、`TR_SPAWN_STEP` の relative
  または PATH lookup 前提の設定は runner 実行前に移行してください。`HERMES_STEP_CMD`、
  `HERMES_PROBE_CMD`、`TR_PUSH_CMD` は whitespace で分割して argv 配列にし、PATH 解決される
  通常の実行可能ファイル名も使えます。
- `TR_LEDGER_FOLD_TOTAL_MAX_BYTES` は attempt ごとの sentinel fold budget（既定 16 MiB）です。
  `TR_LEDGER_FOLD_MAX_BYTES` は bounded fold loop の chunk size（既定 4 MiB）であり、pass 全体の
  上限ではありません。total budget を使い切った attempt は以後 permanent に fold-quiescent となり、
  receipt は `fold_complete:false` のままです。

feature-era の各 task artifact には append-only の `ledger.jsonl` があります。writer は task runner
だけです。runner は `init` を追加し、各 attempt の `sentinel-events.jsonl` の complete line を
driver 所有の task/attempt/run/seq identity で fold し、version 付き task-level `task_end` を projection
します。不正な source line も `schema:"raw"` と `parse_error:true` を付けて保持し、budget または
oversize による loss は `fold_done`、`fold_oversize_line`、terminal な `fold_exhausted` に明示します。
ledger failure は fail-open の telemetry failure であり、delivered/DLQ transition を rollback しません。

`task-end.json` は atomic な task-level receipt です。最初の `ts`、`started_at`、`outcome`、
`terminal_reason` は immutable です。reconcile は folded-state fingerprint が変わった場合だけ
`receipt_version` を増やして evidence aggregate を修復し、`fold_complete` を再計算します。また、
現 receipt version の valid な ledger projection が 1 件あることを独立に保証します。`delivered` は
常に `completed`、DLQ は final driver classification が `window-error` の場合だけ `overflowed`、
それ以外は `aborted` です。sentinel の `window_error` は evidence であり outcome を決めません。

### Claude Code overflow sentinel の環境変数

Claude Code adapter は CLI を spawn する前に次の値を検証します。不正値は exit 2 です。
`OVF_SENTINEL` が unset または空なら、CLI selector の `OVF_STEP_CMD` 以外の sentinel 設定は無視され、
sentinel の動作も無効です。CLI は `prompt.md` を stdin から直接受け取り、export 済み
`TR_STEP_TIMEOUT_S` の全 budget を維持し、stdout は変わらず、sentinel artifact は 1 つも作られません。

| 変数 | 契約 |
| --- | --- |
| `OVF_SENTINEL` | unset/空 = off。それ以外は厳密に `shadow` または `active` |
| `OVF_T_ABS` | optional の 1 以上の整数。設定時のみ forward — unset なら閾値の解決順（明示上書き > per-model 表 > 製品既定 `80000`）で解決し、どの段が勝ったかを key ごとに `run_meta.threshold_sources` へ記録 |
| `OVF_W_PCT` | optional の 1–99 の整数、100 で割って変換。設定時のみ forward — unset は `OVF_T_ABS` と同じ解決（製品既定 `0.50`） |
| `OVF_MODEL_ALIASES` | optional の JSON object。model-id alias → canonical id の写像（string、trim+lowercase、single-step で連鎖なし）。不正な値は spawn 前に exit 2 |
| `OVF_MODEL_THRESHOLDS` | optional の JSON object `{"models": {"<exact-id-or-glob>": {"T_abs"?, "w"?}}, "N_drift"?, "theta_drift"?}`。entry は key ごとの部分上書き。matching は canonical 完全一致 > 最長リテラル接頭辞の glob（`*` のみ）。重複 key・未知 key・リテラル接頭辞が同一の pattern の組・範囲外の値は spawn 前に exit 2。placeholder 既定は `N_drift` `5` / `theta_drift` `0.10`。表は空で出荷され、書き戻しまで全 model が明示/既定の段で解決 |
| `OVF_CTX_WINDOW` | optional の 1 以上の整数。context-window 梯子の第 1 段 |
| `OVF_HF_CONFIG` | optional の local・non-symlink HF `config.json` path（またはその directory）。network lookup なし |
| `OVF_HF_NETWORK` | unset/空/`0` = 無効、`1` = best-effort の HF network rung を有効化 |
| `OVF_HF_CACHE_DIR` | `OVF_HF_NETWORK=1` のとき必須。leaf path 自体は symlink でない writable cache dir で、cache-entry file の leaf も symlink 不可（ancestor の symlink は許容）。作成時/再利用時に mode `0700` を強制 |
| `OVF_COMPACTION_OWNER` | `sentinel` または `host`。unset は warning 後 `sentinel`、`host` は `disabled-host` を記録 |
| `OVF_STEP_CMD` | whitespace 分割の CLI argv。既定 `claude -p --output-format stream-json --verbose` |
| `OVF_FINALIZE_TIMEOUT_S` | 1 以上の整数。既定 `10`。CLI 終了後の monitor join 上限 |
| `CLAUDE_MODEL` | 実際の model identifier。unset は `claude-unknown` を記録し、catalog lookup 前に `default` へ short-circuit されるため `claude-` catalog prefix には一致しない |

context-window は config、検証済み local HF config、opt-in の HF network cache rung、
Claude-family prefix catalog、200k 既定の順で解決します。network rung は `CLAUDE_MODEL` を
plain な HF repo id として検証し、stdlib `urllib` で
`https://huggingface.co/<model>/resolve/main/config.json` を hard 5 秒 timeout で 1 回だけ取得し、
`OVF_HF_CACHE_DIR` 配下の flat な `sha256(model).json` cache entry へ atomic に書いてから、
その cache entry を同じ 1 MiB 制限で再読込して採用します。cache directory の leaf と
cache-entry file の leaf はどちらも symlink 不可で、ancestor の symlink は許容します。
network payload と cached entry はどちらもその上限ちょうどまでは受け入れ、1 byte でも大きければ reject します。採用 source は `config`、`hf-config`、
`hf-network-cached`、`catalog`、`default` のいずれかで記録します。placeholder の
`claude-unknown` は catalog lookup 前に `default` へ short-circuit されます。HF id の検証、cache の検証、cache I/O、
fetch の失敗は stderr へ warning を 1 行出したうえで、model-step の exit status を変えずに
catalog/default へ fall through します。

TTFB は run start から最初の `assistant` stream line までです。token tier は 90 秒、前 attempt の
last injected MA が厳密に 50k 超なら 150 秒、厳密に 100k 超なら 240 秒です。prior state がない場合と
未収載 model は 240 秒です。記名 reasoning floor は `claude-opus*` 240 秒、`qwen3*` 180 秒、
`qwq*` 300 秒、`glm-5*` 300 秒、`grok-*` 300 秒、`deepseek-r1*` 600 秒、
`o1*`/`o3*` 600 秒です。これらは `alert` を記録するだけで CLI を終了しません。

`system/compact_boundary` を観測すると measured series を reset し、pending nudge を取り下げ、
`runtime_compaction=true` を記録します。この event がない場合は injected が厳密に 40% 超急落したかを
見る heuristic が fallback です。異なる大きさの turn が混在すると、本来有効な nudge を 1 回だけ
抑制することがありますが、これは v1 で受容する bounded false-positive cost です。

turn 間で model または runtime が変わると、切替 turn でちょうど 1 回の regime reset が走ります
（canonical な model identity は trim+lowercase に `OVF_MODEL_ALIASES` の single-step lookup を
適用したもの。identity field を欠く turn は比較もresetもしません）。reset は measured series・
pending nudge・軸ごとの nudge hysteresis・drift accumulator をクリアし、model-keyed config を
すべて再解決します — context window（run-level の `OVF_CTX_WINDOW` 上書きは引き続き最優先）、
閾値解決順による `T_abs`/`w`、TTFB floor。from/to identity・解決値・key ごとの source を持つ
`regime_change` event を記録し、切替 turn を新 regime の sample 1 として評価します。
compaction の急落 heuristic は regime 境界をまたいで評価されません。persist された regime
identity により、attempt 境界での model 切替 retry も検出されます。

さらに各 regime の tap 自体を突合します（第 3 の計器状態:「計器が嘘をついた」。「発火しなかった」
「見えていなかった」と並ぶ区別です）。Claude Code adapter は `drift_reference: derived` を申告し、
turn ごとの生 usage object をそのまま保存します。core が毎 turn ledger 上で正規化を再適用し、`N_drift` turn ごとに
paired cumulative sum を比較して（参照を欠く turn は cadence を進めつつ両辺の和から対で
除外）、`|bias_ratio| > theta_drift` で episode 起動・方向非依存の `tap_drift` event を、regime 内で
生 usage の field set が変われば `schema-change` episode を記録します。v1 は記録のみで、`tap_drift`
が発火・nudge・無効化を起こすことはなく、derived の count は provider drift の証拠になりません。

hysteresis で block された predicate crossing は event flood 防止のため意図的に `fire` を追加しません。
append-only の `turn` series から再構成できます。slope-only fire では level threshold を跨いでいないため、
`threshold_hit` を省略します。

`sentinel-events.jsonl` は append-only で、`turn`、`fire`、`alert`、`regime_change`、
`tap_drift`、run ごとの `attempt_end` を収録します。turn record は `runtime` を持ち、drift
capability が `none` でない限り生の `raw_usage` object をそのまま持ちます。`attempt_end` と
fold 後の task-level receipt は `regime_change_resets`、`tap_drift_count`（episode 数）、
`drift_reference_status`（task 内の全 regime の最弱 capability）を持ちます。task runner は
これらを per-task ledger へ fold し、上記の distinct な task-level `task_end` を emit します。
`attempt.json` は厳密に `schema_version`、`task_id`、`attempt`、`mode`、`model`、
`ctx_window`、`ctx_window_source`、`started_at`、nullable な `first_byte_at`、
`cli_exit_code`、`tap_status_final`、`fired`、`events_path` の field で atomic に確定します。attempt identity は
zero-padding を保った attempt directory basename string です。timeout または signal death では model が
書いた `step-result.json` を `step-result.json.partial` へ quarantine します。
event field の契約は [overflow sentinel DESIGN](design/159-overflow-sentinel/DESIGN.md) の §3–§6 を
参照してください。

---

## 契約文書

| 文書 | 契約 |
| --- | --- |
| [DESIGN.md](design/DESIGN.md) | learning-loop contract、verification seam、promotion rule、adapter contract |
| [DESIGN-task-runner.md](design/DESIGN-task-runner.md) | task-runner contract、budget、DLQ、metric |
| [159 overflow sentinel DESIGN](design/159-overflow-sentinel/DESIGN.md) | overflow predicate、tap、TTFB、event、nudge の契約 |
| [governance-rules.md](governance-rules.md) | family adoption governance canon（governance R1–R14・amendment status と effectiveness gate） |
| [plugin-convention.md](plugin-convention.md) | plugin seam contract と extraction policy |
| [plugins.md](plugins.md) | known plugin registry と attachment status |
| [updater-rollout.md](updater-rollout.md) | release-tag updater rollout と運用制約 |

## adapter インストール文書

| Runtime | 文書 |
| --- | --- |
| Claude Code | [adapters/claude-code/INSTALL.md](../adapters/claude-code/INSTALL.md) |
| Codex CLI | [adapters/codex/INSTALL.md](../adapters/codex/INSTALL.md) |
| Kimi Code CLI | [adapters/kimi/INSTALL.md](../adapters/kimi/INSTALL.md) |
| Hermes Agent | [adapters/hermes/INSTALL.md](../adapters/hermes/INSTALL.md) |
| OpenClaw | [adapters/openclaw/INSTALL.md](../adapters/openclaw/INSTALL.md) |
