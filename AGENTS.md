# Repository Instructions

このリポジトリでは、Claude Code / Codex などの AI Agent 用スキルを公開 GitHub リポジトリとして管理する。

## 基本方針

- 回答・ドキュメントは日本語を基本にする。
- 公開リポジトリなので、秘密情報・API key・認証情報・個人用 cache をコミットしない。
- スキルは `skills/<skill-name>/` に配置し、各スキルに `SKILL.md` と `README.md` を置く。
- `~/.claude` / `~/.codex` / plugin cache / system skill からの丸ごとコピーは避け、管理対象にするスキルだけを明示的に取り込む。
- `CLAUDE.md` は `@AGENTS.md` の参照だけにする。

## スクリプト

- symlink 操作用 script は冪等にする。
- 既存の実体ディレクトリや別 symlink を上書き削除せず、必要な場合は backup に退避する。
- `make status` は読み取り専用で、リンク状態の確認だけを行う。

## Git

- コミットメッセージは英語で、`feat:` / `fix:` / `refactor:` / `test:` / `docs:` / `chore:` / `ci:` / `build:` の prefix を使う。
- push 前に `git status -sb --untracked-files=all` と `git diff --check` を確認する。
- shell コマンドは `rtk` prefix を優先する。
