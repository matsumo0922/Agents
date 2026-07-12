# issue-pr-autopilot

GitHub issue や短い作業説明を起点に、兄弟 worktree で実装、コミット、PR 作成、reviewer サブエージェントによるレビュー、修正反復までを自走させるためのスキルです。

dig / design / issue-pr-autopilot は 1 つのパイプライン bundle として配布されます（`make link` で一括リンク）。単体配布はサポートしません。設計の形式は design スキルの `references/design-contract.md`（設計契約）が正本で、本スキルは構造検査に必要な最小限を gate schema として持ちます。

## 使いどころ

- issue URL や issue 番号を渡して、そのまま PR 作成まで進めたいとき
- main agent に進行管理と判断だけをさせ、実装・検証・レビューをサブエージェントに分けたいとき
- PR 上に round 1 のレビューとレビューサマリー付き APPROVED コメントを残しながら、修正と再レビューを繰り返したいとき

## 設計の要点

実行速度・トークン効率・収束性のため、次の規律を中心に設計しています。

- **main agent は判断専任**: 実装・検証コマンド実行・ソースのフル読みをせず、worker / reviewer の構造化レポートで判断する。ゲート判定はすべて構造検査。サブエージェントが停止しても代行せず、新しいサブエージェントに引き継がせる
- **受理ゲート G2〜G5**: G2 = 設計の gate schema 適合（必須セクション・条件付き matrix の発動・非該当宣言）、G3 = worker evidence matrix の受理（全行の具体性・production call path・SHA 一致。「全件修正済み」の要約だけの報告は不受理）、G4 = レビュー開始前の検証台帳 SHA と HEAD の照合、G5 = APPROVED 条件（safety/migration/security の unchecked なし + 最終 HEAD の full validation + PR description 同期）
- **設計ゲートと反証**: 設計が無い複数レイヤー変更は designer が設計契約準拠で設計し、客観条件リスト（cross-layer / safety / migration / security / 複数 consumer / DB hot path）に該当すれば clean context の falsifier が設計を反証してから実装に入る。該当判定は main が行う。高リスクな未検証前提は 3 分岐プロトコル（安全性・不可逆性を左右する未確定は停止 / reversible な stage のみ進行 / 既存状態維持のみ fail-safe 仮決め）で扱う
- **スコープ分割 gate**: 設計のスコープ判定が「1 worker / 1 reviewer で網羅不能」なら、自走時は第 1 stage のみ実装して `Refs #<issue>` の PR とし、残 stage は issue に分割提案コメントを投稿する。元の受け入れ条件は stage mapping で保持する
- **worker evidence matrix**: 完了報告は「条件 / 実装箇所 / production call path / 証明テスト名 / 検証結果 + SHA」の evidence matrix が必須。レビュー修正は finding cluster 単位で同根経路を列挙してから一括修正する
- **検証 tier と信頼チェーン**: 検証結果は「コマンド / 結果 / HEAD SHA / validation scope」の台帳で共有し、reviewer はテストを再実行しない。初回 = full、レビュー修正 = compile + targeted、rebase = affected、最終 HEAD = full（G5 必須）
- **reviewer round 1 は 2 パス**: pass 1 が設計反証（反証 5 ベクトル・非該当宣言の検証・高リスクマークの前提）、pass 2 が実装レビュー（call graph 追跡・evidence 突合・修正コミット固有欠陥クラス）。手順は `references/review-rubric.md`。設計欠陥は worker でなく designer に差し戻す。結果は review point 単位の checked / unchecked matrix で返し、unchecked は PR の「人間に確認してほしいこと」へ転記する
- **round 1 で出し尽くす + 同根の後出し許可**: must-fix は同根クラスの全経路を 1 グループにまとめ「閉じる条件」を付ける。round 2 以降で同根の未調査経路を発見した場合の新規指摘は禁止せず「round 1 網羅漏れ」ラベルで明示する
- **cycle / round の分離と計測**: 外部レビューは常に、CI failure・rebase は material な場合のみ新 cycle とし、round は cycle 内で数え直す。cycle ごとに finding origin・regression 件数・時間 4 区分（wall-clock / cumulative compute / critical-path / external wait）を計測ログに記録し、最終 APPROVED コメントへ cycle 表として転記する
- **GitHub 投稿の最小化**: PR に投稿するのは round 1 レビューと最終 APPROVED コメント（サマリー + 指摘対応表 + cycle 表）のみ。PR description の更新は main の責務
- **役割別モデルティア**: designer / falsifier / reviewer = 最上位ティア高 effort、実装 worker = 速度と消費優先。環境ごとの具体的な割当は SKILL.md の「環境別ヒント」に定義
- **進捗はメッセージではなく worktree 観察**: 実行中の worker への進捗確認メッセージはターンを乱すため送らず、worker worktree の git log / status / diff を読み取り専用で観察する。停滞判定は経過時間ではなく worktree の無変化で行う

## ファイル

- `SKILL.md`: スキル本体。goal 設定、gate schema、コンテキストノート、設計ゲートと反証パス、worktree 作成、検証 tier、worker / reviewer への指示、受理ゲート、PR description の形式、レビュー反復、cycle 定義と計測、環境別ヒントを定義します。
- `references/review-rubric.md`: reviewer round 1 の 2 パス手順、review point matrix の形式、evidence matrix 突合基準。
- `agents/openai.yaml`: UI メタ情報です。

## リンク

リポジトリ root で以下を実行すると、`~/.claude/skills/issue-pr-autopilot` と `~/.codex/skills/issue-pr-autopilot` に symlink を作成できます。

```bash
make link
```
