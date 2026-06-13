# issue-pr-autopilot

GitHub issue や短い作業説明を起点に、兄弟 worktree で実装、コミット、PR 作成、reviewer サブエージェントによるレビュー、修正反復までを自走させるためのスキルです。

## 使いどころ

- issue URL や issue 番号を渡して、そのまま PR 作成まで進めたいとき
- main agent に進行管理をさせ、実装 worker と reviewer を分けたいとき
- PR 上にレビューコメントまたは APPROVED コメントを残しながら、修正と再レビューを繰り返したいとき

## ファイル

- `SKILL.md`: スキル本体。goal 設定、worktree 作成、実装 worker / reviewer への指示、PR description の形式、レビュー反復を定義します。
- `agents/openai.yaml`: UI メタ情報です。

## リンク

リポジトリ root で以下を実行すると、`~/.claude/skills/issue-pr-autopilot` と `~/.codex/skills/issue-pr-autopilot` に symlink を作成できます。

```bash
make link
```
