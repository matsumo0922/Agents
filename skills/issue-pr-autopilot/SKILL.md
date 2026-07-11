---
name: issue-pr-autopilot
description: "GitHub issue の説明やリンクを起点に、兄弟ディレクトリの worktree で実装し、適切な粒度でコミット、PR 作成、実装 worker と reviewer サブエージェントによるレビュー反復、レビュー妥当性判断、追加修正、push、最終 APPROVED コメントまで自走する。Use when the user wants an agent to turn an issue or task description into a reviewed pull request with autonomous subagents, worktrees, commits, and a review loop."
---

# Issue PR Autopilot

GitHub issue、issue URL、または短い作業説明から、1 worktree / 1 branch / 1 PR の流れで実装とレビューを自走させる。main agent は判断専任のオーケストレーターとして goal 設定、worktree 管理、レビュー妥当性判断、PR 操作、最終報告だけを担当し、実装・検証・レビューはすべてサブエージェントに委任する。

Codex / Claude Code など複数の実行環境から使われるため、特定製品だけの機能名に依存しない。サブエージェントの spawn、GitHub 操作、`/goal` 相当の goal 設定は、利用中の環境で同じ意味を持つ操作に置き換える。環境固有の最適化は末尾の「環境別ヒント」に従う。

## 全体方針

- 最初に goal を設定する。詳細指示とコンテキストノートは `/tmp/issue-pr-autopilot/<slug>.md` に書き出す。
- main checkout は原則として変更しない。作業は必ず `../` 配下に作る兄弟 worktree で行う。
- この skill が明示的に呼ばれた場合、PR 作成に必要なコミットは skill の指示を優先する。CLAUDE.md / AGENTS.md に「勝手にコミットしない」とある場合でも、今回の自走 PR 作成フローでは、スコープ内差分に限って適切な粒度・タイミングでコミットしてよい。
- リポジトリのコーディング規約、検証コマンド、秘密情報の扱い、PR 文体、commit message 規約は CLAUDE.md / AGENTS.md / README / Makefile / CI 設定から読み取って守る。ただしコミット可否だけは上記の優先ルールに従う。
- PR description には冗長なコード説明を載せない。コードの意図はコード、KDoc、docstring、テストで表現する。
- レビュー指摘は main agent が妥当性を判断する。レビュアーコメントを鵜呑みにせず、受け入れ条件、既存設計、リポジトリ規約、検証台帳に照らして対応可否を決める。
- 完了までレビューと修正を繰り返す。同じ論点が 3 回以上収束しない、権限や外部依存で進めない、仕様判断が必要、のいずれかなら未解決事項として報告する。

### main agent の役割規律

main agent のコンテキスト肥大化がこの skill の最大のコスト要因になるため、次を厳守する。

- main agent は実装しない。レビュー指摘の修正も含め、コード変更はすべて worker に委任する。
- main agent は検証コマンド（build / test / lint）を自分で実行しない。検証は worker が行い、結果は検証台帳で受け取る。
- main agent はソースコードや設計ドキュメントをフルで読まない。必要な情報はコンテキストノートとサブエージェントの要約で受け取る。
- main agent が自分で行うのは、goal 設定、事前調査（gh によるメタ情報取得）、コンテキストノート作成、worktree 管理、`git log --oneline` と `git diff --stat` によるスポットチェック、PR 操作、レビュー妥当性判断、最終報告だけ。
- worker / reviewer が停止・応答不能になった場合（usage limit、クラッシュ等）でも、main agent が実装やレビューを代行しない。コンテキストノート、対応表、検証台帳、直前までの進捗を渡して新しいサブエージェントを spawn し、続きから引き継がせる。

### トークンと再実行の規律

- サブエージェントは diff 全文・ログ全文・ファイル本文を main agent に返さない。要約と参照（パス、SHA、URL）だけを返す。
- 一度取得した issue 本文・PR 情報・CI 結果は使い回す。同一クエリの再実行（同じ issue への `gh issue view` を繰り返す等）を禁止する。
- CI 待ちは sleep によるポーリングを繰り返さず、`gh pr checks --watch` のような待機コマンド 1 回にまとめる。
- サブエージェントをネストしない（worker / reviewer が自分のサブエージェントをさらに spawn しない）。中継しかしないサブエージェントを作らない。調査が必要な場合、観点が重なる調査は 1 体にまとめる。
- 同一 worktree で検証コマンドを並列実行しない（出力が衝突してやり直しになる）。検証は 1 回の呼び出しにまとめる（例: Gradle は 1 コマンドに複数タスクを渡す）。

## Goal 設定

goal は次の形で設定する。`/goal` が使える環境では `/goal` として設定し、使えない環境では同じ内容を自分の完了条件として保持する。

```text
/goal /tmp/issue-pr-autopilot/<slug>.md を読み、その指示に従って issue 実装、worktree 作成、PR 作成、レビュー反復、検証、最終報告まで完了する。終了条件はファイル内の <completion_criteria> をすべて満たすこと。
```

goal ファイル（コンテキストノート）には少なくとも次を含める。

```text
<completion_criteria>
1. 対象 issue または作業説明の受け入れ条件を満たす実装がある
2. ../ 配下の専用 worktree に、英語 prefix 付き commit が意味のある粒度で存在する
3. PR が open で、タイトルは英語、description は日本語で本 skill の形式に従っている
4. PR に round 1 のレビューコメント（指摘があった場合）と、レビューサマリー付きの最終 APPROVED コメントがある
5. main agent がレビューの妥当性を判断し、妥当な must-fix / should 指摘に対応済み
6. 検証台帳の最終エントリの SHA が HEAD と一致し、検証コマンドが成功している
7. 人間の判断待ち、未解決事項、検証不能事項が PR と最終報告に記録されている
</completion_criteria>
```

## 事前調査とコンテキストノート

main agent は実装前に次を確認する。

```bash
gh auth status
gh repo view --json nameWithOwner,defaultBranchRef
git status -sb --untracked-files=all
git worktree list
git branch --show-current
```

- issue URL または issue 番号がある場合は `gh issue view <number> --comments` を **1 回だけ**実行し、本文、受け入れ条件、議論、関連 PR を読む。
- 調査結果はコンテキストノート `/tmp/issue-pr-autopilot/<slug>.md`（goal ファイルと同一でよい）に書き出す。含めるもの: 作業内容、受け入れ条件、スコープ外、base branch、検証コマンド、リポジトリ規約の要点、設計コンテキスト（後述）。以後、main agent とすべてのサブエージェントはこのノートを参照し、同じ調査を繰り返さない。
- 説明だけが渡された場合は、ノート内に「作業内容」「受け入れ条件」「スコープ外」を明文化する。
- base branch はユーザー指定を優先し、なければ remote default branch を使う。
- 検証コマンドは CLAUDE.md / AGENTS.md / README / Makefile / package.json / Gradle / CI 設定から推定する。分からない場合は最小の lint / test / build を選ぶ。
- `local.properties`、`.env`、認証ファイルなど、worktree で検証に必要な未追跡ファイルを確認する。秘密情報はコミットしない。

### 設計コンテキストの引き継ぎ

impl ↔ review の往復を減らす最大の要素は、設計判断を worker / reviewer に正確に引き継ぐことにある。コンテキストノートには「設計コンテキスト」セクションを必ず設け、次を書く（該当がない項目は「なし」と明記する）。

- 採用したアプローチとその理由
- 検討して不採用にした代替案と、不採用の理由
- 変更予定ファイルマップ（ファイル → 何をするか）
- 既知のリスク・エッジケースと、その扱いの決定事項
- 議論済みの仕様判断（「〜とする」の決定事項として書く。「〜が望ましい」の曖昧な形で書かない）
- この変更固有のレビュー観点（reviewer の一次チェックリストになる。例: ページングの安定性、fail-closed の維持、後方互換）

情報源の優先順位は「このセッション内の設計議論・設計レビュー > issue 本文とコメント」とする。どちらにも設計が無い場合は設計ゲート（後述）に従い、main agent の推定だけで設計コンテキストを埋めない（要件の言い換えにしかならない）。同一セッションで設計議論が行われている場合、その結論は要約ではなく決定事項としてすべて転記する。issue 本文またはコメントに「## 設計」セクションがある場合は、その内容を取り込む。転記後、サブエージェントを spawn する前に「会話・issue で合意した設計判断のうちノートに載っていないものはないか」を確認する。

## 設計フェーズとの連携

設計はこの skill の実行と別セッション・別マシンで行われることがある。セッションと実行環境を跨いで設計を引き継げる共有ストアは GitHub issue だけなので、設計を行ったエージェントが issue を作成・更新する場合は、issue 本文に次の形式の「## 設計」セクションを含める。この skill は事前調査でこのセクションを回収し、コンテキストノートの「設計コンテキスト」に展開する。

```markdown
## 設計

### 採用アプローチ

<アプローチと理由>

### 不採用案

<代替案と不採用の理由。なければ「なし」>

### 変更予定ファイル

<ファイル → 変更内容の一覧>

### エッジケースと決定事項

<既知のリスク・エッジケースと決定した扱い>

### レビュー観点

<この変更固有に確認すべき観点>
```

### 設計ゲート

セッション内の設計議論も issue の「## 設計」も無い場合、worker を spawn する前に次で分岐する。

- 変更が単一レイヤーで自明な場合: ノートの設計コンテキストに「設計: 不要と判断」と理由を明記して進む。
- 変更が複数レイヤーに跨る場合、ユーザーに質問できる状況なら、質問ツールで「(a) 設計サブエージェントを走らせてから実装（推奨）/ (b) 設計なしで進める / (c) 中断して設計セッションで行う（design skill が使える環境ではそれを使う）」を確認する。自走中で質問できない場合は (a) を選ぶ。
- (a) では設計サブエージェントを 1 体 spawn し、成果物を issue の「## 設計」セクションとして投稿してからノートに展開する。設計サブエージェントが「未決定」として返した高リスク論点は、レビュー反復の「仕様判断が必要」プロトコル（issue へ質問 + 仮決めで続行）に乗せる。

```text
<designer_instruction>
あなたは設計サブエージェントです。コードを変更せず、実装前の設計だけを行ってください。

<scope>
- コンテキストノート: /tmp/issue-pr-autopilot/<slug>.md（作業内容・受け入れ条件・スコープ外が書いてある。必読）
- 対象リポジトリ: <main checkout の絶対パス>（読み取りのみ）
</scope>

<rules>
禁止: コード・ドキュメントの変更 / 自分のサブエージェントの spawn / issue 本文の再取得。

- 関連コードを読み、「## 設計」の形式（採用アプローチ / 不採用案 / 変更予定ファイル / エッジケースと決定事項 / レビュー観点）で設計する。
- 変更予定ファイルは「ファイル → 何をするか」の粒度まで具体化する。新規コンポーネントは置き場所（module / package）と責務を決める。
- 決定事項は「〜とする」の形で書く。決められない高リスク論点は理由付きで「未決定」として列挙する。
- コンテキストノートのスコープ外に踏み込む設計をしない。
</rules>

<deliverables>
main agent には、issue にそのまま投稿できる「## 設計」セクション全文と、未決定の高リスク論点の一覧だけを返してください。コード本文は返さないでください。
</deliverables>
</designer_instruction>
```

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

## 検証の信頼チェーン

同じ環境・同じ worktree でテストを何度も叩き直すのはこの skill の主要な浪費源のため、検証結果は台帳で 1 回だけ共有する。

- worker は検証を実行するたびに、検証台帳エントリ「コマンド / 結果 / 実行時 HEAD SHA」を報告する。
- reviewer は build / test / lint を**再実行しない**。検証台帳を信頼し、コードだけをレビューする。
- 再検証が必要になるのは「最後に検証した SHA から HEAD が動いたとき」だけ。そのときも実行するのは修正を行った worker であり、main agent や reviewer ではない。
- 最終確認時、検証台帳の最終エントリの SHA が HEAD と一致していれば再実行しない。一致しない場合のみ worker に最終検証を 1 回実行させる。

## 実装 worker への指示

main agent は実装 worker サブエージェントを明示的に spawn し、次の形式で依頼する。利用環境のサブエージェント機能に合わせて文言だけ調整してよい。レビュー指摘の修正も同じ worker（コンテキストを引き継げる環境では同一スレッドの継続、難しければ対応表を渡した再依頼）に任せる。

```text
<worker_instruction>
あなたは実装 worker です。main agent の代わりに、指定 worktree 内だけで issue を実装してください。

<scope>
- コンテキストノート: /tmp/issue-pr-autopilot/<slug>.md（必読。作業内容、受け入れ条件、スコープ外、検証コマンドが書いてある）
- worktree: <absolute path>
- branch: <branch>
- base: <base branch>
</scope>

<rules>
禁止: main checkout・他 worktree の変更 / 無関係なリファクタ・別 issue の先取り / 秘密情報の追加 / 自分のサブエージェントの spawn / issue 本文の再取得（gh issue view の再実行）/ 検証が失敗した状態での完了報告（解決できない場合は失敗理由を報告する）。

- まずコンテキストノートを読み、「設計コンテキスト」の設計・決定事項に従って実装する。簡略化や別アプローチの方が良いと考えた場合は、実装を進める前に理由付きで main agent に判断を仰ぐ（黙って別解にしない）。
- worktree の CLAUDE.md / AGENTS.md にノート未記載の規約があれば読んで従う。
- スコープ内差分は適切な粒度・英語 prefix 付きでコミットする。変更前後で `git status -sb --untracked-files=all` と `git diff` を確認し、意図したファイルだけ stage する。
- 検証コマンドは 1 回の呼び出しにまとめ、並列実行しない。
- 機能名・クラス名・コマンド名を追加・変更したら、影響するドキュメント（README / docs/ / KDoc）を同じ PR 内で更新し、変更した名前で docs/ と README を grep して誤りになった記述が残っていないことを確認する。ドキュメントは現在の仕様を現在形で書き、変更の経緯や将来の予定を書かない。
- 関数のシグネチャや呼び出し規約を変えたら、呼び出し元を grep で全件洗い出して追随する（テストコード含む）。
- 新しい安全機構・新機能には、手組みの入力だけで通る unit テストに頼らず、本番の配線経由で実際に発動することを確認するテストを含める。
- レビュー指摘（must-fix / should）の修正は、対症療法で終わらせず根本原因を特定し、同じ根の問題が他の層・他の箇所に残っていないか grep で確認して一括で修正する。
- push の直前に `git fetch origin <base-branch>` と `git rebase origin/<base-branch>` を実行する。conflict は自分で解消し、rebase で HEAD が変わったら検証を 1 回やり直して検証台帳を更新する。
- 報告前にセルフレビューする: 受け入れ条件の充足 / 規約違反 / スコープ逸脱 / diff の最終確認 / コミット粒度 / ドキュメント影響（grep 確認済みか）。lint や規約レベルの問題はレビューに回さず、この段階で直す。
</rules>

<deliverables>
main agent には次の構造化レポートだけを返してください。diff 全文・ログ全文は返さないでください。
1. 変更ファイル一覧と各変更の 1 行要約
2. commit 一覧（SHA と message）
3. 検証台帳: 実行した検証コマンド / 結果 / 実行時 HEAD SHA
4. PR 作成に使う title / description 案
5. 判断に迷った点、未解決事項、スコープ外にした点
6. 受け入れ条件チェックリスト: ノートの受け入れ条件と「この変更固有のレビュー観点」の各項目について、充足 / 未充足 + 理由を 1 行ずつ
</deliverables>
</worker_instruction>
```

worker の完了報告を受けたら、main agent は `git log --oneline origin/<base-branch>..HEAD` と `git diff --stat` でスポットチェックする。問題があれば worker に追加修正を依頼する。main agent が自分で修正してはならない。

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

- Closes #<issue-number>
- <関連する issue / PR があれば箇条書きで追加。なければ Closes 行のみ>

## 実装目的

<なぜこの変更が必要かを短く書く>

## 実装内容

- <ユーザーが把握すべき粒度の変更点を箇条書き>

<箇条書きだけで伝わらない設計判断や変更の流れがあれば、段落文章で補足する。不要なら省略>

## 検証

### エージェント検証済み

- [x] `<検証コマンド>`（HEAD: <short SHA>）

### 人間に確認してほしいこと

- [ ] <実機確認、UI 目視、デフォルト値の判断など。なければ「なし」>

## ドキュメント影響

<「あり（対象ファイルの列挙）」または「なし」を1行で書く>

## メモ

- <必要な場合のみ書く。不要ならこのセクションごと削除する>
```

コードの詳細説明、実装内部の逐語的な解説、長い設計語りは PR description に載せない。必要な説明はコード、KDoc、docstring、テスト名、または issue コメントに置く。

## Reviewer サブエージェントへの指示（round 1）

PR 作成後、main agent は実装 worker とは別の reviewer サブエージェントを spawn する。round 2 以降は同じ reviewer を継続する（後述）。

```text
<reviewer_instruction>
あなたは reviewer サブエージェントです。コードを編集せず、レビューだけを行ってください。

<target>
- PR: <PR URL>
- コンテキストノート: /tmp/issue-pr-autopilot/<slug>.md（受け入れ条件とスコープが書いてある。必読）
- worktree: <absolute path>
- 検証台帳: <コマンド / 結果 / HEAD SHA>
</target>

<rules>
禁止: build / test / lint の実行（検証台帳を信頼し、コードだけをレビューする）/ issue 本文の再取得・設計ドキュメントのフル読み直し（コンテキストノートを使う）/ 自分のサブエージェントの spawn。

- 利用環境に組み込みのコードレビュー機能があれば、指摘の洗い出しに使ってよい。最終的な指摘の取捨選択と投稿はこの指示に従う。
</rules>

<review_points>
1. 受け入れ条件を満たしているか
2. バグ、エッジケース、レース、互換性、データ破壊、セキュリティ上の問題がないか
3. リポジトリの規約（コンテキストノート記載 + CLAUDE.md / AGENTS.md）に違反していないか
4. テストや検証が妥当か。テストが本番の配線経由で新しい挙動を実際に実行しているか。足りない場合、どのリスクが残るか
5. ドキュメント影響が正しいか。変更された機能名・クラス名・コマンド名で docs/ と README に誤りになった記述が残っていないか、PR description の「ドキュメント影響」が実態と一致しているか
6. PR description が本 skill の形式に収まっているか
7. 設計整合: ノートの設計コンテキスト（採用アプローチ、ファイルマップ、決定事項）から逸脱していないか。逸脱がある場合、main agent が承認した記録があるか
8. ノートの「この変更固有のレビュー観点」を一次チェックリストとしてすべて確認したか。加えて運用時のエッジケース（状態遷移、異常系入力、監査・ログの整合性、並行実行）に踏み込んでレビューしたか
</review_points>

<posting_protocol>
- 指摘がある場合は、GitHub PR に日本語で投稿してください。可能なら PR review として、権限や同一アカウント制約で難しければ `gh pr comment` で `## レビュー (ラウンド 1)` から始まる 1 コメントにまとめてください。各指摘に severity（must-fix / should / nit）と file:line を付けてください。
- 指摘ゼロの場合は GitHub に投稿せず、main agent に APPROVED を報告してください（最終コメントは main agent が投稿します）。
- 根拠のない好み、スコープ外要求、実装方針の押し付けは避けてください。
</posting_protocol>
</reviewer_instruction>
```

reviewer は main agent に次だけ返す。

```text
<review_result>
- round: <N>
- result: APPROVED / COMMENTS
- must-fix: <count> / should: <count> / nit: <count>
- last_reviewed_sha: <レビュー時点の HEAD SHA>
- findings: <各指摘の 1 行要約（severity / file:line / 要旨）>
- checked: <重点的に確認した観点の一覧>
- unchecked: <確認できなかった観点（実機動作、運用時の状態遷移、負荷など）。指摘 0 件の APPROVED でも必ず書くか「なし」と明記>
</review_result>
```

reviewer の unchecked に挙がった観点は、main agent が PR description の「人間に確認してほしいこと」に転記する。内部レビューで確認できていない範囲を人間に明示し、APPROVED 後に外部レビューで指摘が噴き出す二段階構造を緩和する。

## レビュー反復（round 2 以降）

main agent は review_result を読み、各指摘を分類する。

- 妥当な must-fix / should: worker に修正させ、commit と push をさせる。
- 妥当な nit: 対応が安ければ worker にまとめて直させる。対応しない場合は理由を対応表に記録する。
- 不妥当、スコープ外、既存仕様と矛盾: 対応しない理由を対応表に記録する。
- 仕様判断が必要: issue または PR に「質問」「仮決め」「根拠」を日本語で書き、PR description の「人間に確認してほしいこと」にも残す。

指摘ごとの個別返信コメントは投稿しない。対応内容は最終 APPROVED コメントの対応表にまとめて記録する。

修正後の再レビューは次のルールで行う。

- **同じ reviewer を継続する。** コンテキストを引き継げる環境では同一サブエージェントに追加依頼し、難しければ前回の findings と対応表を添えて再依頼する。
- 再レビューの範囲は `git diff <last_reviewed_sha>..HEAD` の変更行と、前回指摘の対応確認**だけ**。未変更コードの再レビューと、未変更行への新規指摘は禁止。新規指摘は修正コミットが持ち込んだ問題に限る。
- 例外: must-fix の修正確認では、修正が対症療法で終わっていないか（同根の問題が他の層に残っていないか）の確認に必要な範囲で、関連する未変更コードを参照してよい。ただし新規指摘は同根の問題に限る。
- 中間ラウンドの結果は GitHub に投稿せず、review_result 形式で main agent に返させる。

```text
<rereview_request>
- round: <N + 1>
- 対応表: <指摘ごとの対応状況。修正済み（short SHA）/ 対応せず + 理由>
- レビュー範囲: git diff <last_reviewed_sha>..HEAD の変更行のみ
- ルール: 未変更コードの再レビューと新規指摘は禁止（修正コミットが持ち込んだ問題と、must-fix 修正の根本対処確認で見つかる同根の問題を除く）。build / test は実行しない。結果は GitHub に投稿せず review_result 形式で返す。
</rereview_request>
```

must-fix / should がゼロになったら reviewer は APPROVED を返す。**nit だけが残っている場合も、残存事項として注記した上で APPROVED を返す。**

APPROVED 後、main agent は検証台帳の最終 SHA と HEAD の一致を確認し（不一致なら worker に最終検証を 1 回実行させ）、次の形式の最終コメントを PR に投稿する。

```markdown
## レビュー結果: APPROVED

### サマリー

- レビューラウンド: <N> 回
- 指摘: must-fix <X> / should <Y> / nit <Z>
- 最終検証: `<コマンド>` 成功（HEAD: <short SHA>）

### 指摘と対応

| # | 指摘（要約） | severity | 対応 |
|---|---|---|---|
| 1 | <要約> | must-fix | 修正済み（<short SHA>） |
| 2 | <要約> | nit | 対応せず: <短い理由> |

### 残存事項

- <未対応 nit の注記、仕様判断待ち。なければ「なし」>
```

指摘がひとつもなかった場合は「指摘と対応」の表を省略してよい。

## 最終報告

完了時はユーザーに次を簡潔に報告する。

- PR URL
- branch / worktree
- commit 範囲
- レビューラウンド数と指摘の内訳
- 検証台帳の最終エントリ（コマンド / 結果 / SHA）
- 人間の判断待ち、未解決事項、検証不能事項

worktree は削除せず残す。削除や merge はユーザーから明示指示がある場合だけ行う。merge を指示された場合は mergeability を確認してから 1 回だけ実行する。

skill 完了後に同じ PR への追加対応（外部レビュー指摘、CI 失敗等）を依頼された場合も、main agent の役割規律を維持する。ビルド・テスト・ロジック変更を伴う対応は worker の継続または再 spawn で委任し、検証不要な軽微修正だけ main agent が直接行ってよい。

## 環境別ヒント

コア原則: 役割ごとにモデルティアと effort を分ける。多ターンの実装 worker はバランスティア、設計とレビューは最上位ティアを使う。round 2 以降は同じ reviewer を継続し、前回指摘と新規 diff だけに入力を絞る。Codex では spawn 後の effort を途中変更できると仮定しない。diff・コンテキストノート・既存コードを長く読む役割には最軽量ティアを使わない。サブエージェントを spawn・継続するたびに、割り当てたモデル名と effort をユーザーへの進捗報告に明示する。サブエージェントは数を増やすより、1 回あたりの入力を絞る方が効く。

### Claude Code

- サブエージェント呼び出し時の `model` / `effort` パラメータで役割別に調整する。推奨割当: 実装 worker = Sonnet 5（`effort: high`）、設計サブエージェント / reviewer round 1 = Opus 4.8（`effort: high`）、round 2 以降は同じ reviewer を `low`〜`medium` で継続する。
- 完了したサブエージェントは SendMessage で文脈を保ったまま再開できる。worker / reviewer の継続はこれを使い、再 spawn しない。
- サブエージェントは既定でバックグラウンド実行される。worker の実装中に main agent が PR body の準備などを進めてよい。
- `/code-review` が使える場合、reviewer はこれを指摘の洗い出しに使える。

### Codex

- `~/.codex/agents/` の TOML でエージェント毎に `model` / `model_reasoning_effort` を定義できる。並列上限は `agents.max_threads`（既定 6）。
- 推奨割当: main agent = `gpt-5.6-sol`（`model_reasoning_effort = "medium"`、`plan_mode_reasoning_effort = "high"`）、実装 worker = `gpt-5.6-terra`（`"high"`）、設計サブエージェント = `gpt-5.6-sol`（`"high"`）、reviewer = `gpt-5.6-sol`（`"xhigh"`）。
- round 2 以降も同一 reviewer thread と `"xhigh"` を維持する。継続依頼では前回の findings、対応表、`git diff <last_reviewed_sha>..HEAD` だけを渡し、全体を再読させない。spawn 後の thread に対して effort を変更できると仮定しない。
- `gpt-5.6-luna` は primary role に割り当てない。context をほとんど積まない機械的な補助作業に限る。
- `model_reasoning_effort` の `max` / `ultra` は使わない。`max` は `xhigh` に対する消費増が大きく、`ultra` はモデル内部の subagent 委任が本 skill のオーケストレーションと二重になる。
- clean context が必要な reviewer は `spawn_agent` の `fork_turns = "none"`、直近の会話を引き継ぐ worker は必要最小限の `fork_turns` を指定する。`agent_type` と併用できる。
- reviewer の継続は同一サブエージェントスレッドへの追加依頼で行う。
- 組み込みの `/review` は read-only の専用レビュアーで、対象リポジトリの AGENTS.md に「Review guidelines」節を書くと指摘基準を調整できる。
- 同一 GitHub アカウントでは自分の PR に `gh pr review --approve` できないため、レビューは `gh pr comment` ベースのプロトコルで代替する。
