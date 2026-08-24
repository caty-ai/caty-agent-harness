# タスクパケット — スタッフ向け: Caty Agent Harness を Claude Code に自己インストール

発行: Alpha（配布: 管理者経由）· SoT: caty-ai/caty-agent-harness
対象: スタッフの皆さんの Claude Code 環境（1人1部ずつ使ってください）

---

## 人間の方へ（最初にお読みください — 3分）

このファイルは、**あなたの Claude Code（AI）に渡すための「自己インストール指示書」**です。
使い方は次の3ステップだけです。

1. 管理者から GitHub の招待を受けて、リポジトリを clone できることを確認する
2. Claude Code を開いて、このファイルを読ませてこう頼む：
   **「このタスクパケットに従って Caty Agent Harness をインストールして。Done when の証拠も集めて」**
3. AIが最後に出してくる「Done when チェックリスト＋証拠」を、そのまま管理者に送る

作業はAIが自分でやります。あなたのファイルを壊さない設計です（追記のみ・何度実行しても安全）。
所要はだいたい30分〜1時間です。分からないことが起きたら、途中経過ごと管理者に送ってください。

---

## AIへ: Why（最初に読むこと）

あなた（Claude Code エージェント）は優秀だが、セッションが終わると学びを忘れ、自己評価は
自分に甘く、コツは文脈に死蔵され、中断すると現在地を見失う。このハーネスはその4つを
ファイルと規律で解決する：STATE.md（セッションを越える運用記憶）、rubric 先出し＋独立検証、
検証合格分だけのスキル昇格（それまでは `skills/_staging/` で検疫）、CHECKPOINT（付箋）。
導入前に repo の README.md（10分）と [DESIGN.md](../../docs/design/DESIGN.md) §3（5分）を読むこと。
先行導入4件（Cero/Claire/Luca ほか）ではローカル環境との食い違いが必ず出た — **手順書より
実環境を優先し、逸脱は理由つきで報告**すればよい。

## AIへ: What to do

対象ワークスペース＝**この人が日常的に Claude Code を使うプロジェクトのルート**（人間に確認
してから進める。迷ったら最もよく使う1つに入れる。後から増やせる）。

1. リポジトリを安定した場所へ clone する（例: `~/tools/caty-agent-harness`）。
2. `./install.sh --workspace <対象ワークスペース>` を実行（冪等・既存ファイル不変更）。
3. `./install.sh --workspace <対象ワークスペース> --bootstrap-runtime claude-code --append-bootstrap <対象ワークスペースの絶対パス/CLAUDE.md>` を実行
   （CLAUDE.md がなければ作成してよい。マーカー式なので二重追記されない）。
4. CHECKPOINT Stop hook を登録する: `adapters/claude-code/INSTALL.md` の手順どおり、
   ユーザーの `settings.json` の Stop hooks に `checkpoint-stop-hook.sh` を追加。
   **既存の hooks 設定は消さず追記**。登録後、設定の JSON が壊れていないことを確認。
5. `./install.sh --check --workspace <対象ワークスペース>` を実行し、警告ゼロを確認。
6. **練習タスクを1周する**（ループの体得が目的）: 「このワークスペースの構成を README 1枚に
   まとめる」程度の小さな成果物タスクを、①rubric 先書き（`loop/RUBRIC.tmpl.md` 使用）
   ②作業 ③**新しい別セッション**を人間に開いてもらい、依頼文+rubric+成果物だけ渡して採点
   ④合格なら STATE.md の Lessons に1行 ⑤`loop/handoffs/` に申し送りを書き、`## Last session` の entry 1 を追加して既存 entry をそのまま下へ送る ⑥終了、の6拍子で実施。
7. 人間に「今後の運用」を1分で説明する: 頼み方は今まで通り／たまに STATE.md を見ると
   AIの学習が読める／月1回 `--check`。

## AIへ: Constraints

- **追記のみ**。既存の CLAUDE.md・settings.json・プロジェクトファイルを書き換えない/消さない。
- APIキーや秘密情報をチャット・STATE.md・リポに書かない（このパケットの範囲では新しい
  キーは一切不要）。
- `skills/_staging/` のものを勝手に本採用（`skills/` へ移動）しない — 昇格は検証合格後のみ。
- 報告は**このセッションのツール実行結果で裏が取れることだけ**。未確認事項は「未確認」と明記。
- 途中で環境と手順が食い違ったら、実環境を優先して差分を Done when に書く。

## Done when（証拠つきで人間に渡し、人間が管理者へ転送）

- [ ] レイアウト完成: `find <ws>/loop <ws>/skills -maxdepth 2` の出力
- [ ] bootstrap 追記済み: CLAUDE.md 末尾の `# caty-agent-harness bootstrap v2` ブロックの tail
- [ ] Stop hook 登録済み: settings.json の該当行 + 動作確認1回
      （STATE.md を触らずにワークスペースのファイルを1つ変えて終了→ブロックが出ること）
- [ ] `--check` 警告ゼロ: 実行出力の全文
- [ ] 練習タスク1周: rubric・成果物パス・別セッション採点の verdict・STATE.md 追記行
- [ ] 逸脱リスト（なければ「なし」と明記）

## 補足（人間向け）

- 検証（採点）役は、当面は「新しい Claude Code セッション」で十分です。作業した
  セッションと**別の文脈**であることが本質で、別会社のAIを使う構成（クロスベンダー）は
  慣れてからのアップグレードで大丈夫です。
- アップデートは clone した場所で `git pull` → `./install.sh --check`。皆さんのノート
  （STATE.md）やスキルには触りません。
- 困ったら: README の「困ったとき」→ それでもダメなら管理者へ。
