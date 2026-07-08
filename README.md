# Agents

Claude Code / Codex などの AI Agent で使うドキュメントやスキルを管理し、GitHub 経由で複数 PC から同じ内容を参照するためのリポジトリです。

`skills/` 配下のスキルと `rules/` 配下の共通指示ファイルを配布します。

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
rules/
  AGENTS.md
  kotlin.md
  lint/
    detekt.yml
    .editorconfig
    README.md
scripts/
  link-skills.sh
  link-rules.sh
Makefile
AGENTS.md
CLAUDE.md
```

## 基本方針

- 回答・ドキュメントは日本語を基本にします。
- Claude Code と Codex の両方から扱える内容として管理します。
- スキルの配布は `~/.claude/skills` / `~/.codex/skills` への symlink で行います。
- Codex 向け共通指示の配布は `~/.codex/AGENTS.md` への symlink で行います。
- Claude Code 向け共通指示の配布は `~/.claude/CLAUDE.md` の wrapper 生成で行います。
- 公開リポジトリなので、秘密情報・API key・認証情報・個人用 cache はコミットしません。
- 全プロジェクト共通のルール本文は `rules/AGENTS.md` に集約します。エージェントの挙動・ドキュメント・メモリ・Git 運用のルールを置き、判断を伴わない整形規約は置きません。
- Kotlin / Jetpack Compose プロジェクト向けの規約は `rules/kotlin.md` に置き、各プロジェクトの CLAUDE.md / AGENTS.md から参照して使います。静的解析で判定できる規約は `rules/lint/` のテンプレートを取り込んだ detekt / compose-rules 設定で強制します。

## セットアップ

リンク状態を確認します。

```bash
make status
```

スキルと共通指示ファイルを配布します。

```bash
make link
```

Claude Code だけにリンクしたい場合は `TARGETS` を指定します。

```bash
TARGETS=claude make link
```

このリポジトリから作成した symlink と generated wrapper だけを外します。

```bash
make unlink
```

スキルと共通指示ファイルは個別にも操作できます。

```bash
make status-skills
make status-rules
make link-skills
make link-rules
make unlink-skills
make unlink-rules
```

## 注意

- 既存の実体ディレクトリや別 symlink がある場合、`link` は削除せず `~/.agents-repo-backups/<timestamp>/` へ退避します。
- `unlink` はこのリポジトリを指している symlink と generated wrapper だけを削除します。
- `scripts/link-skills.sh` は `skills/` 配下だけを配布対象にします。
- `scripts/link-rules.sh` は `rules/AGENTS.md` を配布対象にします。
- `~/.claude/CLAUDE.md` は `rules/AGENTS.md` と `~/.claude/RTK.md` を参照する generated wrapper として作成します。
- `~/.claude/AGENTS.md` は作成しません。`CLAUDE.md` の wrapper だけを配布し、`AGENTS.md` 直読みがある環境でも二重注入しない構成にします。
- `~/.codex/AGENTS.md` は symlink です。`rtk init -g --codex` やエディタでの編集は `rules/AGENTS.md` に write-through するため、RTK 初期化は `make link` の前に実行し、リンク後に設定を変更した場合は `rtk git status -sb --untracked-files=all` で正本が汚れていないことを確認します。
- cache・session・認証情報・個人用設定はコミットしません。

## 管理中のスキル

- [codex-orchestrator](skills/codex-orchestrator/README.md): Codex CLI の `/goal` 指示ファイルを生成し、複数作業をサブエージェントへ委任するためのスキル。
- [dig](skills/dig/README.md): プランの暗黙の前提と未検討リスクを、構造化質問の反復インタビューで掘り起こすためのスキル。
- [issue-pr-autopilot](skills/issue-pr-autopilot/README.md): issue や作業説明を起点に、worktree 実装、PR 作成、レビュー反復まで自走させるためのスキル。
