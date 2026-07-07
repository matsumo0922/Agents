# Agents

Claude Code / Codex などの AI Agent で使うドキュメントやスキルを管理し、GitHub 経由で複数 PC から同じ内容を参照するためのリポジトリです。

`skills/` 配下のスキルを `~/.claude/skills` と `~/.codex/skills` へ symlink で配布します。

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

## 基本方針

- 回答・ドキュメントは日本語を基本にします。
- Claude Code と Codex の両方から扱える内容として管理します。
- スキルの配布は `~/.claude/skills` / `~/.codex/skills` への symlink で行います。
- 公開リポジトリなので、秘密情報・API key・認証情報・個人用 cache はコミットしません。
- `CLAUDE.md` は `@AGENTS.md` の参照だけにし、ルール本文は `AGENTS.md` に集約します。

## セットアップ

スキルのリンク状態を確認します。

```bash
make status
```

`skills/` 配下のスキルを `~/.claude/skills` と `~/.codex/skills` へ symlink します。

```bash
make link
```

Claude Code だけにスキルをリンクしたい場合は `TARGETS` を指定します。

```bash
TARGETS=claude make link
```

このリポジトリから作成したスキル symlink だけを外します。

```bash
make unlink
```

## 注意

- 既存の実体ディレクトリや別 symlink がある場合、`link` は削除せず `~/.skills-repo-backups/<timestamp>/` へ退避します。
- `unlink` はこのリポジトリを指している symlink だけを削除します。
- `scripts/link-skills.sh` は `skills/` 配下だけを配布対象にします。
- cache・session・認証情報・個人用設定はコミットしません。

## 管理中のスキル

- [codex-orchestrator](skills/codex-orchestrator/README.md): Codex CLI の `/goal` 指示ファイルを生成し、複数作業をサブエージェントへ委任するためのスキル。
- [dig](skills/dig/README.md): プランの暗黙の前提と未検討リスクを、構造化質問の反復インタビューで掘り起こすためのスキル。
- [issue-pr-autopilot](skills/issue-pr-autopilot/README.md): issue や作業説明を起点に、worktree 実装、PR 作成、レビュー反復まで自走させるためのスキル。
