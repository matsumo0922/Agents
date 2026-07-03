# issue-pr-autopilot

GitHub issue や短い作業説明を起点に、兄弟 worktree で実装、コミット、PR 作成、reviewer サブエージェントによるレビュー、修正反復までを自走させるためのスキルです。

## 使いどころ

- issue URL や issue 番号を渡して、そのまま PR 作成まで進めたいとき
- main agent に進行管理と判断だけをさせ、実装・検証・レビューをサブエージェントに分けたいとき
- PR 上に round 1 のレビューとレビューサマリー付き APPROVED コメントを残しながら、修正と再レビューを繰り返したいとき

## 設計の要点（v2）

実行速度とトークン効率のため、次の規律を中心に設計しています。

- **main agent は判断専任**: 実装・検証コマンド実行・ソースのフル読みをせず、worker / reviewer の構造化レポートで判断する
- **検証の信頼チェーン**: 検証結果は「コマンド / 結果 / HEAD SHA」の台帳で共有し、reviewer はテストを再実行しない。再検証は HEAD が動いたときだけ
- **コンテキストノート**: issue 本文や規約の調査は 1 回だけ行い `/tmp/issue-pr-autopilot/<slug>.md` に書き出し、全サブエージェントが参照する
- **差分スコープの再レビュー**: round 2 以降は同じ reviewer を継続し、前回指摘の対応確認と新規 diff だけを見る
- **GitHub 投稿の最小化**: PR に投稿するのは round 1 レビューと最終 APPROVED コメント（サマリー + 指摘対応表）のみ

## ファイル

- `SKILL.md`: スキル本体。goal 設定、コンテキストノート、worktree 作成、検証の信頼チェーン、worker / reviewer への指示、PR description の形式、レビュー反復、環境別ヒントを定義します。
- `agents/openai.yaml`: UI メタ情報です。

## リンク

リポジトリ root で以下を実行すると、`~/.claude/skills/issue-pr-autopilot` と `~/.codex/skills/issue-pr-autopilot` に symlink を作成できます。

```bash
make link
```
