# codex-orchestrator

Codex CLI の `/goal` 指示ファイルを生成し、複数の作業単位をサブエージェントへ委任するためのスキルです。

## 使いどころ

- GitHub issue や任意の作業リストを Codex に並列実行させたいとき
- 1 作業 = 1 worktree = 1 branch = 1 PR の形で進めたいとき
- 実装 worker と reviewer worker による PR レビューループを Codex 側で自走させたいとき

## ファイル

- `SKILL.md`: スキル本体。バッチ設計、事前調査、生成チェックリストを定義します。
- `prompt-template.md`: `/tmp/codex-goals/<batch>.md` に展開するための指示ファイルテンプレートです。

## リンク

リポジトリ root で以下を実行すると、`~/.claude/skills/codex-orchestrator` と `~/.codex/skills/codex-orchestrator` に symlink を作成できます。

```bash
make link
```

既存の実体ディレクトリがある場合は削除せず、`~/.skills-repo-backups/<timestamp>/` へ退避します。
