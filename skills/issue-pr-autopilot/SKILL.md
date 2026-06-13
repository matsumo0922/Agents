---
name: issue-pr-autopilot
description: "GitHub issue の説明やリンクを起点に、兄弟ディレクトリの worktree で実装し、適切な粒度でコミット、PR 作成、実装 worker と reviewer サブエージェントによるレビュー反復、レビュー妥当性判断、追加修正、push、PR コメント返信まで自走する。Use when the user wants an agent to turn an issue or task description into a reviewed pull request with autonomous subagents, worktrees, commits, and a review loop."
---

# Issue PR Autopilot

GitHub issue、issue URL、または短い作業説明から、1 worktree / 1 branch / 1 PR の流れで実装とレビューを自走させる。main agent はオーケストレーターとして goal 設定、worktree 管理、レビュー妥当性判断、最終報告を担当し、実装とレビューはサブエージェントに委任する。

Codex / Claude Code など複数の実行環境から使われるため、特定製品だけの機能名に依存しない。サブエージェントの spawn、GitHub 操作、`/goal` 相当の goal 設定は、利用中の環境で同じ意味を持つ操作に置き換える。

## 全体方針

- 最初に goal を設定する。`/goal` が使える環境では `/goal` で、長い指示は `/tmp/issue-pr-autopilot/<slug>.md` に書き出して「このファイルを読み、completion criteria を満たすまで実行する」という短い goal にする。
- main checkout は原則として変更しない。作業は必ず `../` 配下に作る兄弟 worktree で行う。
- この skill が明示的に呼ばれた場合、PR 作成に必要なコミットは skill の指示を優先する。CLAUDE.md / AGENTS.md に「勝手にコミットしない」とある場合でも、今回の自走 PR 作成フローでは、スコープ内差分に限って適切な粒度・タイミングでコミットしてよい。
- リポジトリのコーディング規約、検証コマンド、秘密情報の扱い、PR 文体、commit message 規約は CLAUDE.md / AGENTS.md / README / Makefile / CI 設定から読み取って守る。ただしコミット可否だけは上記の優先ルールに従う。
- PR description には冗長なコード説明を載せない。コードの意図はコード、KDoc、docstring、テストで表現する。
- レビュー指摘は main agent が妥当性を判断する。レビュアーコメントを鵜呑みにせず、受け入れ条件、既存設計、リポジトリ規約、実行結果に照らして対応可否を決める。
- 完了までレビューと修正を繰り返す。同じ論点が 3 回以上収束しない、権限や外部依存で進めない、仕様判断が必要、のいずれかなら未解決事項として報告する。

## Goal 設定

短い作業なら次の形で goal を設定する。

```text
/goal <issue または作業説明> を実装する。../ に専用 worktree を作成し、実装 worker に委任して検証済みコミットを作成し、PR を作成する。別 reviewer サブエージェントに PR レビューを依頼し、GitHub PR 上にレビューまたは APPROVED コメントを投稿させる。main agent はレビューの妥当性を判断し、妥当な指摘に対応して push と返信を行い、APPROVED かつ検証成功になるまで反復する。完了条件は、PR が open、最終 HEAD で検証成功、PR に APPROVED のレビューまたはコメントが存在し、未解決事項が PR と最終報告に記録されていること。
```

指示が長い場合は `/tmp/issue-pr-autopilot/<slug>.md` に詳細を書き、goal は次の形にする。

```text
/goal /tmp/issue-pr-autopilot/<slug>.md を読み、その指示に従って issue 実装、worktree 作成、PR 作成、レビュー反復、検証、最終報告まで完了する。終了条件はファイル内の <completion_criteria> をすべて満たすこと。
```

goal ファイルには少なくとも次を含める。

```text
<completion_criteria>
1. 対象 issue または作業説明の受け入れ条件を満たす実装がある
2. ../ 配下の専用 worktree に、英語 prefix 付き commit が意味のある粒度で存在する
3. PR が open で、タイトルは英語、description は日本語
4. PR に reviewer サブエージェントのレビュー履歴と最終 APPROVED コメントがある
5. main agent がレビューの妥当性を判断し、妥当な must-fix / should 指摘に対応済み
6. 最終 HEAD でリポジトリに適した検証コマンドが成功している
7. 人間の判断待ち、未解決事項、検証不能事項があれば PR と最終報告に記録されている
</completion_criteria>
```

## 事前調査

main agent は実装前に次を確認する。

```bash
gh auth status
gh repo view --json nameWithOwner,defaultBranchRef
git status -sb --untracked-files=all
git worktree list
git branch --show-current
```

- issue URL または issue 番号がある場合は `gh issue view <number> --comments` で本文、受け入れ条件、議論、関連 PR を読む。
- 説明だけが渡された場合は、goal ファイル内に「作業内容」「受け入れ条件」「スコープ外」を明文化する。
- base branch はユーザー指定を優先し、なければ remote default branch を使う。
- 検証コマンドは CLAUDE.md / AGENTS.md / README / Makefile / package.json / Gradle / CI 設定から推定する。分からない場合は最小の lint / test / build を選ぶ。
- `local.properties`、`.env`、認証ファイルなど、worktree で検証に必要な未追跡ファイルを確認する。秘密情報はコミットしない。

## Worktree 作成

worktree 名と branch 名は issue 番号または短い英語 slug から作る。

```bash
git fetch origin <base-branch>
git worktree add ../<repo-name>-<issue-or-slug> -b <branch-name> origin/<base-branch>
```

推奨形式:

- branch: `agent/<issue-number>-<english-slug>`、または `agent/<english-slug>`
- worktree: `../<repo-name>-<issue-number>-<english-slug>`、または `../<repo-name>-<english-slug>`
- commit: `feat: ...` / `fix: ...` / `refactor: ...` / `test: ...` / `docs: ...` / `chore: ...` / `ci: ...` / `build: ...`

worktree 作成後、必要な未追跡設定ファイルがある場合だけコピーする。コピーしたファイルは `.gitignore` に守られていることを確認する。

## 実装 worker への指示

main agent は実装 worker サブエージェントを明示的に spawn し、次の形式で依頼する。利用環境のサブエージェント機能に合わせて文言だけ調整してよい。

```text
<worker_instruction>
あなたは実装 worker です。main agent の代わりに、指定 worktree 内だけで issue を実装してください。

<scope>
- 対象: <issue URL / issue 番号 / 作業説明>
- worktree: <absolute path>
- branch: <branch>
- base: <base branch>
- スコープ内: <やること>
- スコープ外: <やらないこと>
</scope>

<rules>
- まず worktree の CLAUDE.md / AGENTS.md / README / Makefile / CI 設定を読み、コーディング規約と検証方法を把握してください。
- issue がある場合は `gh issue view <number> --comments` で本文と議論を読んでください。
- main checkout や他 worktree は変更しないでください。
- 無関係なリファクタ、別 issue の先取り、秘密情報の追加は禁止です。
- この skill は PR 作成まで自走するため、スコープ内差分は適切な粒度でコミットしてください。コミットメッセージは英語 prefix 付きにしてください。
- 変更前後で `git status -sb --untracked-files=all` と `git diff` を確認し、意図したファイルだけ stage してください。
- 検証コマンドを実行し、成功結果または失敗理由を main agent に報告してください。
</rules>

<deliverables>
1. 実装済み差分
2. 意味のある粒度の commit
3. 実行した検証コマンドと結果
4. PR 作成に使う title / description 案
5. 判断に迷った点、未解決事項、スコープ外にした点
</deliverables>
</worker_instruction>
```

worker の完了報告を受けたら、main agent は差分と commit を確認する。問題があれば worker に追加修正を依頼するか、main agent が最小限の修正を入れて commit する。

## PR 作成

PR 作成前に main agent は対象 worktree で次を確認する。

```bash
git status -sb --untracked-files=all
git diff --check
git log --oneline origin/<base-branch>..HEAD
```

PR は GitHub 連携ツールが使える場合はそれを優先し、難しければ `gh` を使う。branch は tracking 付きで push する。

```bash
git push -u origin <branch>
gh pr create --base <base-branch> --head <branch> --assignee @me --title "<English PR title>" --body-file <body-file>
```

PR は原則 ready-for-review で作成する。ユーザーが draft を指定した場合だけ draft にする。

PR description は日本語で、次の構成にする。

```markdown
## 関連 Issue

Closes #<issue-number>

## 実装目的

<なぜこの変更が必要かを短く書く>

## 実装内容

- <ユーザーが把握すべき粒度の変更点>

## 検証方法

- [x] `<command>`

## メモ

- <判断待ち、制約、追跡したいことがあれば短く書く。なければ「なし」>
```

コードの詳細説明、実装内部の逐語的な解説、長い設計語りは PR description に載せない。必要な説明はコード、KDoc、docstring、テスト名、または issue コメントに置く。

## Reviewer サブエージェントへの指示

PR 作成後、main agent は実装 worker とは別の reviewer サブエージェントを spawn する。2 回目以降のレビューでは、同じ reviewer の前回コンテキストが引き継げる環境ならそれを使い、難しければ前回レビューコメント、対応 commit、差分要約を渡す。

```text
<reviewer_instruction>
あなたは reviewer サブエージェントです。コードを編集せず、GitHub PR 上にレビュー結果を投稿してください。投稿後、指摘の有無を main agent に報告して終了してください。

<target>
- PR: <PR URL>
- issue: <issue URL or none>
- worktree: <absolute path>
- round: <N>
- 前回レビュー: <round 2 以降は前回コメントと対応状況>
</target>

<review_points>
1. issue / 作業説明の受け入れ条件を満たしているか
2. バグ、エッジケース、レース、互換性、データ破壊、セキュリティ上の問題がないか
3. リポジトリの CLAUDE.md / AGENTS.md / README / CI 規約に違反していないか
4. テストや検証が妥当か。足りない場合、どのリスクが残るか
5. PR description が関連 issue、実装目的、実装内容、検証方法、メモの範囲に収まっているか
</review_points>

<posting_protocol>
- 可能なら GitHub の PR review として投稿してください。APPROVE できる権限と別アカウント条件が満たせない場合は、`gh pr comment` で代替してください。
- 指摘がある場合は `## レビュー (ラウンド <N>)` で始め、各指摘に severity（must-fix / should / nit）と file:line を付けてください。
- 指摘ゼロの場合は、PR review の approve、または `## レビュー結果: APPROVED` で始まる PR コメントを投稿してください。
- 根拠のない好み、スコープ外要求、実装方針の押し付けは避けてください。
- GitHub に書く内容は日本語にしてください。
</posting_protocol>
</reviewer_instruction>
```

reviewer は投稿後、main agent に次だけ返す。

```text
<review_result>
- PR: <URL>
- round: <N>
- result: APPROVED / COMMENTS
- must-fix: <count>
- should: <count>
- nit: <count>
- comment URL or summary: <...>
</review_result>
```

## レビュー反復

main agent は reviewer の結果を読み、各指摘を分類する。

- 妥当な must-fix / should: 修正する。worker に戻すか main agent が修正し、commit、push、PR 上で日本語返信する。
- 妥当な nit: 必要に応じて対応する。対応しない場合は理由を PR 上に返信する。
- 不妥当、スコープ外、既存仕様と矛盾: 対応しない理由を PR 上に日本語で返信する。
- 仕様判断が必要: issue または PR に「質問」「仮決め」「根拠」を日本語で書き、PR description のメモにも残す。

修正後は次の情報を添えて reviewer に再レビューを依頼する。

```text
<rereview_request>
- PR: <URL>
- round: <N + 1>
- 前回指摘: <要約>
- 対応 commit: <SHA と概要>
- 対応しなかった指摘: <理由>
- 再確認してほしい観点: <差分中心>
</rereview_request>
```

APPROVED まで繰り返す。APPROVED 後、main agent は最終 HEAD で検証コマンドを再実行し、PR に必要なら最終コメントを残す。

## 最終報告

完了時はユーザーに次を簡潔に報告する。

- PR URL
- branch / worktree
- commit 範囲
- レビューラウンド数と結果
- 実行した検証コマンドと結果
- 人間の判断待ち、未解決事項、検証不能事項

worktree は削除せず残す。削除や merge はユーザーから明示指示がある場合だけ行う。
