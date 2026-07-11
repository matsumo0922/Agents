# issue-pr-autopilot

GitHub issue や短い作業説明を起点に、兄弟 worktree で実装、コミット、PR 作成、reviewer サブエージェントによるレビュー、修正反復までを自走させるためのスキルです。

## 使いどころ

- issue URL や issue 番号を渡して、そのまま PR 作成まで進めたいとき
- main agent に進行管理と判断だけをさせ、実装・検証・レビューをサブエージェントに分けたいとき
- PR 上に round 1 のレビューとレビューサマリー付き APPROVED コメントを残しながら、修正と再レビューを繰り返したいとき

## 設計の要点（v2）

実行速度とトークン効率のため、次の規律を中心に設計しています。

- **main agent は判断専任**: 実装・検証コマンド実行・ソースのフル読みをせず、worker / reviewer の構造化レポートで判断する。サブエージェントが停止しても代行せず、新しいサブエージェントに引き継がせる
- **設計コンテキストの引き継ぎ**: セッション内の設計議論や issue の「## 設計」セクションを決定事項としてノートに転記し、worker / reviewer が同じ設計を参照する。worker は設計から逸脱する前に報告し、reviewer は設計整合と変更固有のレビュー観点を確認する
- **設計ゲート**: 設計が見つからない複数レイヤー変更は、main agent の推定で埋めずに、ユーザーへの質問または最上位ティアの設計サブエージェントで設計を確定し、issue に「## 設計」として投稿してから worker を spawn する
- **検証の信頼チェーン**: 検証結果は「コマンド / 結果 / HEAD SHA」の台帳で共有し、reviewer はテストを再実行しない。再検証は HEAD が動いたときだけ
- **コンテキストノート**: issue 本文や規約の調査は 1 回だけ行い `/tmp/issue-pr-autopilot/<slug>.md` に書き出し、全サブエージェントが参照する
- **差分スコープの再レビュー**: round 2 以降は同じ reviewer を継続し、前回指摘の対応確認と新規 diff だけを見る
- **未確認観点の申告**: reviewer は APPROVED 時も確認できなかった観点を申告し、main agent が PR の「人間に確認してほしいこと」に転記する
- **GitHub 投稿の最小化**: PR に投稿するのは round 1 レビューと最終 APPROVED コメント（サマリー + 指摘対応表）のみ
- **役割別モデルティア**: Codex では main = Sol medium、設計 = Sol xhigh、実装 = Sol medium、レビュー = Sol xhigh。round 2 以降は同じ reviewer と effort を維持し、前回指摘と新規 diff だけに入力を絞る。環境ごとの具体的な割当は SKILL.md の「環境別ヒント」に定義
- **進捗はメッセージではなく worktree 観察**: 実行中の worker への進捗確認メッセージはターンを乱すため送らず、worker worktree の git log / status / diff を読み取り専用で観察する。停滞判定は経過時間ではなく worktree の無変化で行う

## ファイル

- `SKILL.md`: スキル本体。goal 設定、コンテキストノート、設計コンテキストの引き継ぎ、worktree 作成、検証の信頼チェーン、worker / reviewer への指示、PR description の形式、レビュー反復、環境別ヒントを定義します。
- `agents/openai.yaml`: UI メタ情報です。

## リンク

リポジトリ root で以下を実行すると、`~/.claude/skills/issue-pr-autopilot` と `~/.codex/skills/issue-pr-autopilot` に symlink を作成できます。

```bash
make link
```
