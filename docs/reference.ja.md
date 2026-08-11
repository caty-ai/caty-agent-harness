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

flush intake consumer の会計 ledger は `loop/pending/intake-runs.log` です。deadman の `distill` marker が証明するのは intake が実行されたことだけです。内容レベルの沈黙・dedup・deferral・eviction・quarantine の各件数は ledger で確認します。`loop/archive/` は append-only で、自動で prune されることはありません。ledger の詳しい形式と schedule は [adapters/claude-code/INSTALL.md](../adapters/claude-code/INSTALL.md) を参照してください。

## task-runner の実行境界

- task frontmatter の `receipt:` は
  `^out/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$` に一致し、`.` と `..` の segment を
  含んではいけません。delivery にはさらに、その target が symlink ではない non-empty な
  regular file で、解決後も task artifact の `out/` 配下にあることが必要です。
- donecheck fence は column zero から始めます。heredoc 内の column-zero fence も文字列として
  extraction を終了させるため、使用禁止です。
- donecheck に渡るのは `TASK_ID`、`TASK_FILE`、`ARTIFACT_DIR`、`TR_DC_CWD`、固定の
  `PATH=/usr/bin:/bin:/usr/sbin:/sbin`、`HOME`、runner 側で set 済みの
  `LANG`/`LC_ALL`/`TZ`、および shell が作る変数だけです。それ以外の継承変数は消え、
  依存していた check は次回実行時に明示的に失敗します。
- `TR_SPAWN_STEP` は1個の argv として実行され、実行可能な通常ファイルへの絶対パスが必須です。
  relative または PATH lookup 前提の provider 設定は runner 実行前に移行してください。

---

## 契約文書

| 文書 | 契約 |
| --- | --- |
| [DESIGN.md](../DESIGN.md) | learning-loop contract、verification seam、promotion rule、adapter contract |
| [DESIGN-task-runner.md](../DESIGN-task-runner.md) | task-runner contract、budget、DLQ、metric |
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
