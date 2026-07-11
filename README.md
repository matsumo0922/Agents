# Agents

Claude Code / Codex などの AI Agent で使うドキュメントやスキルを管理し、GitHub 経由で複数 PC から同じ内容を参照するためのリポジトリです。

`skills/` 配下のスキルと `rules/` 配下の共通指示ファイルを配布します。

## 構成

```text
skills/
  design/
    SKILL.md
    README.md
    agents/openai.yaml
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
  link-project-rules.sh
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

Codex の PC ごとの個人環境設定は [docs/codex-local-setup.md](docs/codex-local-setup.md) を参照します。

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

## Kotlin プロジェクトへの規約配布

`rules/kotlin.md` と `rules/lint/` は、Kotlin プロジェクトごとに opt-in で配布します。

```bash
make link-project PROJECT=~/dev/App/OneNavi
make status-project PROJECT=~/dev/App/OneNavi
make unlink-project PROJECT=~/dev/App/OneNavi
```

`link-project` は次を行います。

- プロジェクトの `AGENTS.md` に `rules/kotlin.md` の全文をマーカー付き管理ブロック（`<!-- agents-rules:kotlin:begin -->` 〜 `end`）として注入・更新します。プロジェクト固有の記述はそのまま残ります。
- プロジェクトの `CLAUDE.md` が無ければ `@AGENTS.md` の1行で作成します。既にある場合は変更せず、`@AGENTS.md` 参照が無ければ warn を表示します。
- `rules/lint/` の `detekt.yml`（→ `config/detekt/detekt.yml`）と `.editorconfig` を、存在しない場合のみコピーします（copy-once。以後の調整はプロジェクト側の所有物です）。

`rules/kotlin.md` を更新したら、各プロジェクトで `make link-project` を再実行して管理ブロックを更新します。`make status-project` が `stale` を表示した場合が再実行のサインです。

## 注意

- 既存の実体ディレクトリや別 symlink がある場合、`link` は削除せず `~/.agents-repo-backups/<timestamp>/` へ退避します。
- `unlink` はこのリポジトリを指している symlink と generated wrapper だけを削除します。
- `scripts/link-skills.sh` は `skills/` 配下だけを配布対象にします。
- `scripts/link-rules.sh` は `rules/AGENTS.md` を配布対象にします。
- `scripts/link-project-rules.sh` の管理ブロックはプロジェクトのリポジトリにコミットされる前提です。他のコントリビューターや別 PC でも Agents リポジトリなしでそのまま機能します。
- `unlink-project` は管理ブロックだけを削除します。`CLAUDE.md` と lint ファイルは残します。
- `~/.claude/CLAUDE.md` は `rules/AGENTS.md` と `~/.claude/RTK.md` を参照する generated wrapper として作成します。
- `~/.claude/AGENTS.md` は作成しません。`CLAUDE.md` の wrapper だけを配布し、`AGENTS.md` 直読みがある環境でも二重注入しない構成にします。
- `~/.codex/AGENTS.md` は symlink です。`rtk init -g --codex` やエディタでの編集は `rules/AGENTS.md` に write-through するため、RTK 初期化は `make link` の前に実行し、リンク後に設定を変更した場合は `rtk git status -sb --untracked-files=all` で正本が汚れていないことを確認します。
- cache・session・認証情報・個人用設定はコミットしません。

## 管理中のスキル

- [design](skills/design/README.md): 実装前の設計を architect サブエージェントと構造化質問で確定し、issue の「## 設計」として投稿するためのスキル。
- [dig](skills/dig/README.md): プランの暗黙の前提と未検討リスクを、構造化質問の反復インタビューで掘り起こすためのスキル。
- [issue-pr-autopilot](skills/issue-pr-autopilot/README.md): issue や作業説明を起点に、worktree 実装、PR 作成、レビュー反復まで自走させるためのスキル。
