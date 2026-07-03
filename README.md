# Skills

AI Agent 用のスキルを管理し、GitHub 経由で複数 PC から同じ内容を参照するためのリポジトリです。

## 構成

```text
skills/
  codex-orchestrator/
    SKILL.md
    README.md
    prompt-template.md
  dig/
    SKILL.md
    README.md
    agents/openai.yaml
  issue-pr-autopilot/
    SKILL.md
    README.md
    agents/openai.yaml
scripts/
  link-skills.sh
Makefile
AGENTS.md
CLAUDE.md
```

## セットアップ

リンク状態を確認します。

```bash
make status
```

`~/.claude/skills` と `~/.codex/skills` へ symlink を作成します。

```bash
make link
```

Claude Code だけにリンクしたい場合は `TARGETS` を指定します。

```bash
TARGETS=claude make link
```

作成した symlink だけを外します。

```bash
make unlink
```

## 注意

- 既存の実体ディレクトリや別 symlink がある場合、`link` は削除せず `~/.skills-repo-backups/<timestamp>/` へ退避します。
- `unlink` はこのリポジトリを指している symlink だけを削除します。
- 公開リポジトリなので、cache・session・認証情報・個人用設定はコミットしません。

## 管理中のスキル

- [codex-orchestrator](skills/codex-orchestrator/README.md): Codex CLI の `/goal` 指示ファイルを生成し、複数作業をサブエージェントへ委任するためのスキル。
- [dig](skills/dig/README.md): プランの暗黙の前提と未検討リスクを、構造化質問の反復インタビューで掘り起こすためのスキル。
- [issue-pr-autopilot](skills/issue-pr-autopilot/README.md): issue や作業説明を起点に、worktree 実装、PR 作成、レビュー反復まで自走させるためのスキル。
