# Agents

Claude Code / Codex などの AI Agent で使うドキュメントやスキルを管理し、GitHub 経由で複数 PC から同じ内容を参照するためのリポジトリです。

`skills/` 配下のスキルと `rules/` 配下の共通指示ファイル、`agents/` 配下の agent 定義を配布します。

## 構成

```text
agents/
  gpt-medium.md
  gpt-high.md
  gpt-xhigh.md
skills/
  dig/
    SKILL.md
    README.md
    agents/openai.yaml
  falsify/
    SKILL.md
    README.md
    agents/openai.yaml
  issue-pr-autopilot/
    SKILL.md
    README.md
    scripts/
      validation-lease.sh
    agents/openai.yaml
  japanese-tech-writing/
    SKILL.md
    README.md
  cognitive-rhythm-writing/
    SKILL.md
    README.md
docs/
  cliproxy-setup.md
  codex-local-setup.md
  openspec-guide.md
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
  link-agents.sh
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
- GPT worker agent 定義の配布は `~/.claude/agents/` への symlink で行います。配布先は Claude Code のみで、Codex には agent 定義の概念がないため配布しません。
- 公開リポジトリなので、秘密情報・API key・認証情報・個人用 cache はコミットしません。
- 全プロジェクト共通のルール本文は `rules/AGENTS.md` に集約します。エージェントの挙動・ドキュメント・メモリ・Git 運用のルールを置き、判断を伴わない整形規約は置きません。
- Kotlin / Jetpack Compose プロジェクト向けの規約は `rules/kotlin.md` に置き、各プロジェクトの CLAUDE.md / AGENTS.md から参照して使います。静的解析で判定できる規約は `rules/lint/` のテンプレートを取り込んだ detekt / compose-rules 設定で強制します。

## セットアップ

Codex の PC ごとの個人環境設定は [docs/codex-local-setup.md](docs/codex-local-setup.md) を参照します。

Claude Code から OAuth サブスク枠経由で GPT 系・Claude 系モデルを使うための CLIProxyAPI のセットアップは [docs/cliproxy-setup.md](docs/cliproxy-setup.md) を参照します。

リンク状態を確認します。

```bash
make status
```

スキルと共通指示ファイル、agent 定義を配布します。

```bash
make link
```

スキルと共通指示ファイルについて、Claude Code だけにリンクしたい場合は `TARGETS` を指定します（`link-agents` は配布先が Claude Code のみのため `TARGETS` を参照しません）。

```bash
TARGETS=claude make link
```

このリポジトリから作成した symlink と generated wrapper だけを外します。

```bash
make unlink
```

スキル・共通指示ファイル・agent 定義は個別にも操作できます。

```bash
make status-skills
make status-rules
make status-agents
make link-skills
make link-rules
make link-agents
make unlink-skills
make unlink-rules
make unlink-agents
```

### agent 定義（GPT worker）の運用

`agents/` は CLIProxy 経由で GPT を Claude Code の subagent として使うための agent 定義（`model:` / `effort:` を持つ frontmatter）を置きます。`make link-agents` で `agents/*.md` を `~/.claude/agents/` へファイル単位の symlink として配布します。CLIProxyAPI 自体のセットアップと、この frontmatter 方式を採用した理由は [docs/cliproxy-setup.md](docs/cliproxy-setup.md) を参照してください。

effort 別に使う agent ファイルを増減する場合は、`agents/` にファイルを追加または削除して `make link-agents` / `make unlink-agents` を再実行するだけです。スクリプトは `agents/*.md` を動的に走査するため、ファイル名やスクリプト自体の変更は不要です。

### OpenSpec の導入

issue-pr-autopilot は、対象プロジェクトに [OpenSpec](https://github.com/Fission-AI/OpenSpec) が導入されていることを前提とします。未導入のプロジェクトでは autopilot は停止するか、自明な単一レイヤー変更に限定したフォールバックで動作します。プロジェクトごとに次を実行して導入します。

```bash
npm install -g @fission-ai/openspec@latest
openspec init --tools claude,codex
```

Homebrew にも formula がありますが upstream 非公式のため、公式チャネルの npm を使います。OpenSpec 自体の使い方は [docs/openspec-guide.md](docs/openspec-guide.md) を参照してください。

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
- `scripts/link-agents.sh` は `agents/*.md` を配布対象にし、`~/.claude/agents/` へファイル単位で symlink します。
- `scripts/link-project-rules.sh` の管理ブロックはプロジェクトのリポジトリにコミットされる前提です。他のコントリビューターや別 PC でも Agents リポジトリなしでそのまま機能します。
- `unlink-project` は管理ブロックだけを削除します。`CLAUDE.md` と lint ファイルは残します。
- `~/.claude/CLAUDE.md` は `rules/AGENTS.md` と `~/.claude/RTK.md` を参照する generated wrapper として作成します。
- `~/.claude/AGENTS.md` は作成しません。`CLAUDE.md` の wrapper だけを配布し、`AGENTS.md` 直読みがある環境でも二重注入しない構成にします。
- `~/.codex/AGENTS.md` は symlink です。`rtk init -g --codex` やエディタでの編集は `rules/AGENTS.md` に write-through するため、RTK 初期化は `make link` の前に実行し、リンク後に設定を変更した場合は `rtk git status -sb --untracked-files=all` で正本が汚れていないことを確認します。
- cache・session・認証情報・個人用設定はコミットしません。

## 管理中のスキル

開発パイプラインは [OpenSpec](https://github.com/Fission-AI/OpenSpec) を土台にします（使い方は [docs/openspec-guide.md](docs/openspec-guide.md) を参照）。設計の構造（proposal / delta spec / design / tasks）と仕様の永続化は各プロジェクトに導入した OpenSpec が担い、本リポジトリのスキルはその周辺を受け持ちます。流れは、dig（設計前の対話反証）→ OpenSpec の propose（設計）→ falsify（設計後の独立反証）→ issue-pr-autopilot（propose→apply を駆動する配送シェル）です。falsify と issue-pr-autopilot は依存関係にあるため、1 つの bundle として `make link` で一括配布します。issue-pr-autopilot は falsify を参照するため、単体配布はサポートしません。

- [dig](skills/dig/README.md)：プランの暗黙の前提と未検討リスクを、構造化質問の反復インタビューで掘り起こすためのスキル。Decisions は設計（OpenSpec の propose や issue-pr-autopilot）が要件、事実、仮定として引き継ぎます。
- [falsify](skills/falsify/README.md)：設計や提案を書いた本人以外の clean context が反証する独立反証スキル。反証 5 ベクトル、blocking の処置、帰属タグ、価値判断をユーザーに確定させる質問作法を定めます。
- [issue-pr-autopilot](skills/issue-pr-autopilot/README.md)：issue や作業説明を起点に、OpenSpec の propose→apply を worktree 内で駆動し、反証ゲート、レビューループ、収束判定を経て PR 作成まで自走させる配送シェル。
- [japanese-tech-writing](skills/japanese-tech-writing/README.md)：日本語の技術文書、書籍原稿、記事、解説文を執筆、推敲するための文章規範。
- [cognitive-rhythm-writing](skills/cognitive-rhythm-writing/README.md)：説明的な文章に認知モードの切り替えと未回収の緊張を設計する文章規範。japanese-tech-writing を併用します。
