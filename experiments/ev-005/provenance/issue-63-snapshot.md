# Provenance snapshot: caty-ai/caty-agent-harness#63

Status: **SEALED** (covered by `MANIFEST.sha256`). Captured for amendment A-3.6.

This file exists so the governing design text is preserved inside the sealed, timestamped corpus rather than only on a mutable web page. Per A-3.6 the sealed in-repo files are authoritative where wording differs; this snapshot is provenance, not authority.

## Issue metadata at capture

- title: EV-005: ハーネス有無の統制実験で中核主張を測定（完走率・偽の完了率・介入回数・試行回数）
- state: open
- created: 2026-08-13T11:33:24Z
- last updated: 2026-08-16T01:49:06Z
- author: alpha-mbp-bridge
- comments at capture: 21
- body bytes: 2642
- body sha256: `b798c67464e1ea53c3218a78bba26a92334ac81b727de3945ea15f8674900081`

## Comment index (bodies not inlined; digests make them verifiable)

| # | id | author | created | bytes | sha256 |
| --- | --- | --- | --- | --- | --- |
| 1 | 5280729066 | alpha-mbp-bridge | 2026-08-13T12:58:36Z | 6422 | `eb2bfdaa14e9dbb0c229a42b0d45fab4161a23c1749e7af42dc3750e9e36c2e5` |
| 2 | 5280877720 | alpha-mbp-bridge | 2026-08-13T13:11:28Z | 2889 | `1d41eef2ca07c5572a5c57ed5762b517ad5c7fea007a15736080800a72a986ed` |
| 3 | 5280878057 | alpha-mbp-bridge | 2026-08-13T13:11:30Z | 8426 | `f904b67db8561850e62af4c92ab9fe29dadc7ec495755b7f851ca7fb1449037f` |
| 4 | 5280982844 | alpha-mbp-bridge | 2026-08-13T13:21:05Z | 2012 | `b6d7e5e3086014cfd344ad61087b3fb2db0f995e9796569d99fe482dac13abfe` |
| 5 | 5280983427 | alpha-mbp-bridge | 2026-08-13T13:21:08Z | 6865 | `f86ceb45f9facfa68fd433043f8ae8255a149ecb75a1f5167915cd220e63d170` |
| 6 | 5281139666 | alpha-mbp-bridge | 2026-08-13T13:34:57Z | 437 | `316564bead3947ec51baee92e03c2bda6222fa6a3a77124fb50739a7c51fee0e` |
| 7 | 5281195709 | alpha-mbp-bridge | 2026-08-13T13:39:52Z | 1634 | `56f782c43a3757b1e2aaafbb42779d6e585da61b4859480f55c6ecdcf6375477` |
| 8 | 5283814198 | alpha-mbp-bridge | 2026-08-13T16:57:32Z | 2457 | `66f0ee87c2bb185a286a69bdf09bd7cf6b5d6894d12e0480e88482582731764c` |
| 9 | 5287383810 | alpha-mbp-bridge | 2026-08-13T23:05:24Z | 1625 | `9e513daa346c57fa44b520f330dfa318d9a8bbff190b44a00ba6132e81d083fe` |
| 10 | 5293706310 | caty2 | 2026-08-14T13:14:13Z | 24684 | `768b64c0721f9c5204c2e911b890cc81ca7dbd572c3d44962a6927d24b5bacb5` |
| 11 | 5293804395 | alpha-mbp-bridge | 2026-08-14T13:24:15Z | 3579 | `838f98cd56503a3d9457bc6f023c802966e4bc15b4dd92139c953866db76a7be` |
| 12 | 5294701360 | caty2 | 2026-08-14T14:51:20Z | 24023 | `d2216e532d4a56eb52d13f0ec1166e4cf01326cc34679ce06d384cfaecc20626` |
| 13 | 5294737587 | alpha-mbp-bridge | 2026-08-14T14:54:55Z | 2277 | `627d19fd8175241e10422394c149396e493d861aaf6a7be5f9cad2266ff5d50d` |
| 14 | 5295605010 | caty2 | 2026-08-14T16:18:31Z | 20039 | `a64a89d2f5b5c8fea9bcd5c7519c4c25c141d2e7231349987046d5e6f55cf1d1` |
| 15 | 5295647216 | alpha-mbp-bridge | 2026-08-14T16:22:56Z | 2453 | `f456c6307fce4356dec1761af1a684fd049c2f717ce76eadf6e3c8e0b6872778` |
| 16 | 5299815580 | alpha-mbp-bridge | 2026-08-15T01:28:02Z | 3582 | `ebe08b9fe3f23c4edeb17e0688de65632d0cfe9c9313a776750f61fbbd073e87` |
| 17 | 5303380610 | alpha-mbp-bridge | 2026-08-15T17:24:25Z | 13595 | `9a06846618128201fec72cd641caa6bedc4a1722527958e0c97201af972e396a` |
| 18 | 5303681423 | alpha-mbp-bridge | 2026-08-15T18:40:50Z | 4252 | `868b04aa3c900db0162cf8bf76886c79789a19848243530a9b24b9be73d4d7a0` |
| 19 | 5304038573 | alpha-mbp-bridge | 2026-08-15T20:14:19Z | 3974 | `64c4de360278cfcc1510eea9890e5da5d8e38f8be3296db548f172440a704753` |
| 20 | 5304058340 | alec-bridge | 2026-08-15T20:19:24Z | 438 | `aacac3b4832877aa869c194e9c3f004419602e82c460ffc1fdf12a3e0cafd4a2` |
| 21 | 5305203423 | alpha-mbp-bridge | 2026-08-16T01:49:06Z | 4461 | `cff6cddb9609dd3bbf06f776049d94f92b3a5301a7120d351941a74cb88e9ef9` |

## Issue body, verbatim at capture

```markdown
Lane A of caty-ai/family-os#43（束ね）。**サイズ H**。実装着手前に L/H 3席の設計レビュー必須（L1-9）。

## Why

外部レビュー（2026-08-13）の最重要指摘: 中核主張「AI の偽の完了を機械で潰す」に before/after 証拠が一つもない。`docs/evidence.md` の厳格なフレームワーク（90日失効・反証欄）は存在するのに、中身は地図自身の CI についての証拠のみ。**これが全体の律速段階。**

## 実験設計（凍結前ドラフト・設計レビューで確定）

- **比較**: 同一タスク群を「ハーネス有り / 無し」で実行。同一モデル・同一プロジェクト・同一タスク文面。順序効果を消すため条件順は交互またはランダム
- **規模**: 30〜50本
- **タスク束の構成（オーナー決裁 2026-08-13）**: 実案件中心の混合 — クローズ済み Issue（機械判定可能な Done when を持つもの）の worktree 再演を主体に、型の偏りを補う合成タスクを1〜2割
- **測定指標（4つ）**: ①完走率 ②**偽の完了率**（done と言ったが donecheck が落ちた割合 = 本丸）③人間の介入回数 ④平均試行回数
- **事前登録（必須）**: タスク文と donecheck ブロックを実験開始前に全部書き、SHA-256 を取って公開してから実験を開始する。エージェントが自分の合格基準を書ける懸念（donecheck 著者権限問題）への実験妥当性の担保であり、既存の証拠文化と噛み合う
- **負の結果も記載**: counter-evidence 欄に「うまくいかなかったケース」（例: 短いタスクではオーバーヘッドが上回った）を必ず書く

## Done when

- [ ] 実験設計文書が L/H 3席レビューを通過して凍結されている
- [ ] タスク束 + donecheck の SHA-256 が実験開始前にコミットとして公開されている（事前登録）
- [ ] 全タスクの実行ログ・レシートが再検証可能な形で成果物化されている
- [ ] 4指標の集計結果（生データからの再計算手順つき）がレポートとして本リポジトリに存在する
- [ ] family-os `docs/evidence.md` への EV-005 掲載素材（本文 + counter-evidence + still-don't-know）が引き渡せる状態（掲載自体は Lane I）

## 触るファイル予測

- 新規: `experiments/ev-005/`（タスク束・donecheck・事前登録ハッシュ・実行ログ・レポート）
- 既存コードは触らない（tr-metrics 拡張は Lane B に分離・`scripts/` `lib` 系変更なし）
```
