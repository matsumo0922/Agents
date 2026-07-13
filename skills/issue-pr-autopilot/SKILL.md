---
name: issue-pr-autopilot
description: "GitHub issue の説明やリンクを起点に、兄弟ディレクトリの worktree で実装し、適切な粒度でコミット、PR 作成、実装 worker と reviewer サブエージェントによるレビュー反復、evidence の受理ゲート、レビュー妥当性判断、追加修正、push、最終コメント（APPROVED または残指摘の人間レビュー引き継ぎ）まで自走する。内部レビューは round・時間・diff 成長の予算内で打ち切り、品質保証の最終責任は人間の PR レビューが担う。Use when the user wants an agent to turn an issue or task description into a reviewed pull request with autonomous subagents, worktrees, commits, and a review loop."
---

# Issue PR Autopilot

GitHub issue、issue URL、または短い作業説明から、1 worktree / 1 branch / 1 PR の流れで実装とレビューを自走させる。main agent は判断専任のオーケストレーターとして goal 設定、worktree 管理、受理ゲートの構造検査、レビュー妥当性判断、PR 操作、最終報告だけを担当し、実装・検証・レビューはすべてサブエージェントに委任する。

Codex / Claude Code など複数の実行環境から使われるため、特定製品だけの機能名に依存しない。サブエージェントの spawn、GitHub 操作、`/goal` 相当の goal 設定は、利用中の環境で同じ意味を持つ操作に置き換える。環境固有の最適化は末尾の「環境別ヒント」に従う。

本スキルは dig / design / issue-pr-autopilot からなるパイプライン bundle の一部として配布される（`make link` で一括リンク。単体配布はサポートしない）。設計の形式は design スキルの `references/design-contract.md`（設計契約）が正本で、本スキルはその構造検査に必要な最小限だけを「gate schema」として持つ。

## 全体方針

- 最初に goal を設定する。詳細指示とコンテキストノートは `/tmp/issue-pr-autopilot/<slug>.md` に書き出す。
- main checkout は原則として変更しない。作業は必ず `../` 配下に作る兄弟 worktree で行う。
- この skill が明示的に呼ばれた場合、PR 作成に必要なコミットは skill の指示を優先する。CLAUDE.md / AGENTS.md に「勝手にコミットしない」とある場合でも、今回の自走 PR 作成フローでは、スコープ内差分に限って適切な粒度・タイミングでコミットしてよい。
- リポジトリのコーディング規約、検証コマンド、秘密情報の扱い、PR 文体、commit message 規約は CLAUDE.md / AGENTS.md / README / Makefile / CI 設定から読み取って守る。ただしコミット可否だけは上記の優先ルールに従う。
- PR description には冗長なコード説明を載せない。コードの意図はコード、KDoc、docstring、テストで表現する。
- レビュー指摘は main agent が妥当性を判断する。レビュアーコメントを鵜呑みにせず、受け入れ条件、既存設計、リポジトリ規約、検証台帳に照らして対応可否を決める。
- **品質保証の最終責任は人間の PR レビューにある。** この skill の責務は「証拠と未確認事項が整理され、人間が短時間で判断できる PR」を最短で出すことであり、内部ループで完璧を目指さない。速度は品質と同格の要件として扱う。
- 内部レビューは 1 cycle につき最大 2 round を既定とする。round 2 終了時点で未解消の指摘は修正を続けず、HANDOFF（人間レビューへの引き継ぎ。終了状態の節を参照）として PR に記録して終了する（例外は予算ゲート参照）。権限や外部依存で進めない場合、仕様判断が必要な場合も未解決事項として報告する。

### 予算ゲート（収束の強制）

**自動停止（構造条件）**: 次のいずれかが成立したら、main agent はその場で修正ループを止めて分岐する。修正を積み増して解消を目指さない。

1. 同一指摘 cluster が 2 回 PARTIAL 判定になった（incomplete closure ×2）
2. 指摘への対応が閉じる条件の inventory 外へ拡張し続けている、または設計変更なしでは閉じられない
3. 指摘への対応に新しい layer の追加・新規サブシステムの設計が必要になった（designer の修正規模見積りで判定）

**シグナル（main の判断点。自動停止ではない）**:

- **scope-growth**: PR の diff が round 1 レビュー時点の 2 倍かつ +500 行を超えたら、main は続行 / 停止 / stage-out を明示的に判断して計測ログに記録する（自走中は stage-out 検討に倒す）。
- **SLO 通知**: round 1 のレビュー返却から wall-clock 120 分（external wait を除く）を超えたら、経過と残作業をユーザーへ通知し計測ログに記録する。時間だけを理由に停止しない（validation lease 待ち・CI 待ち・正常進行中の大きな修正を区別できないため。停止判断は上の構造条件で行う）。

**分岐**: 対話中はユーザーに「続行 / HANDOFF（残指摘を人間レビューへ引き継いで終了） / stage 分割」を質問する。自走中の既定は **HANDOFF**。ただし security・データ破壊級の must-fix を未修正のまま HANDOFF はできない: 該当機能を default-off / feature flag / stage-out で PR から隔離してから終了し、隔離もできない場合のみ停止して人間判断を求める。発動したゲート・シグナルと選んだ分岐は計測ログに記録する。

### main agent の役割規律

main agent のコンテキスト肥大化がこの skill の最大のコスト要因になるため、次を厳守する。

- main agent は実装しない。レビュー指摘の修正も含め、コード変更はすべて worker に委任する。設計の欠陥は designer に委任する。
- main agent は検証コマンド（build / test / lint）を自分で実行しない。検証は worker が行い、結果は検証台帳で受け取る。
- main agent はソースコードや設計ドキュメントをフルで読まない。必要な情報はコンテキストノートとサブエージェントの構造化レポートで受け取る。ゲートの判定はすべて構造検査（セクション・行・SHA の有無と具体性）で行う。**adjudication 例外**: 設計欠陥・新 layer 追加・初期 diff の 50% 超を要求する高コスト must-fix に限り、main は該当コード範囲だけを読む（または clean context の adjudicator を 1 体 spawn する）ことで指摘の妥当性を検証してよい。reviewer の過大要求や false positive を検証せずに stage-out・大規模修正へ進まない。
- main agent が自分で行うのは、goal 設定、事前調査（gh によるメタ情報取得と reference 解決確認）、コンテキストノート作成、worktree 管理、`git log --oneline` と `git diff --stat` によるスポットチェック、受理ゲート G2〜G5 の構造検査、falsifier の発動判定、PR 操作（description 更新を含む）、レビュー妥当性判断、対応表と計測ログの管理、最終報告だけ。
- worker / reviewer が停止・応答不能になった場合（usage limit、クラッシュ等）でも、main agent が実装やレビューを代行しない。コンテキストノート、対応表、検証台帳、直前までの進捗を渡して新しいサブエージェントを spawn し、続きから引き継がせる。

### トークンと再実行の規律

- サブエージェントは diff 全文・ログ全文・ファイル本文を main agent に返さない。要約と参照（パス、SHA、URL）だけを返す。
- 一度取得した issue 本文・PR 情報・CI 結果は使い回す。同一クエリの再実行（同じ issue への `gh issue view` を繰り返す等）を禁止する。
- CI 待ちは sleep によるポーリングを繰り返さず、`gh pr checks --watch` のような待機コマンド 1 回にまとめる。実行環境のコマンドタイムアウトで watch が打ち切られた場合は watch の再実行でよい（sleep ループは不可のまま）。
- サブエージェントをネストしない（worker / reviewer が自分のサブエージェントをさらに spawn しない）。中継しかしないサブエージェントを作らない。調査が必要な場合、観点が重なる調査は 1 体にまとめる。
- 同一 worktree で検証コマンドを並列実行しない（出力が衝突してやり直しになる）。検証は 1 回の呼び出しにまとめる（例: Gradle は 1 コマンドに複数タスクを渡す）。

## Gate schema

main agent が G2 / G3 の構造検査に使う最小定義。詳細な形式・記入基準は design スキルの `references/design-contract.md`（サブエージェントが読む）にあり、本 schema と矛盾する場合は契約が正本。

**設計の必須セクション（8 つ）**: 採用アプローチ / 不採用案 / 事実と仮定 / 変更予定ファイル / エッジケースと決定事項 / スコープ判定 / 反証 / レビュー観点。

**条件付き matrix（4 つ）と発動条件の要約**:

- 状態遷移 matrix — safety 機構・保護経路・gate・fail-closed/open に触れる変更。
- consumer matrix — 同一の値・スコープ・例外を複数の消費側へ伝播する変更。
- non-functional contract — DB スキーマ・クエリ・hot path・大量データ処理に触れる変更。
- deployment 手順 — schema migration・permission/role・設定形式の変更。

**非該当宣言**: 条件付き matrix が非該当の場合、エッジケースと決定事項に「<matrix 名>: 非該当（理由 1 行）」の宣言が必要。無言の省略は契約違反。

**layer 定義**: layer = module / process / API 境界 / DB schema / UI / 権限・deployment などの構造境界。変更が 2 つ以上の layer の契約（インターフェース・スキーマ・権限）を同時に変える場合は cross-layer、単一 layer 内の実装詳細に閉じる場合は単一レイヤー。

**falsifier の客観条件リスト**: cross-layer 変更 / safety / migration / security / 複数 consumer / DB hot path。いずれかに該当する設計は clean context の falsifier が必須（該当判定は main が変更予定ファイル map と layer 定義から行い、迷ったら発動する）。

**evidence matrix の列定義**: 条件 | 実装箇所（file:line or シンボル） | production call path（本番エントリポイントからの経路） | 証明するテスト名 | 検証結果 + 実行時 HEAD SHA。

**evidence matrix の受理条件（G3）**:

1. 行 = 受け入れ条件・設計の不変条件・（レビュー修正時は）must-fix の閉じる条件のすべてをカバーしている。
2. 全セルが埋まっている。「対応済み」「修正済み」だけのセルは不受理。
3. production call path が「テストからのみ到達」でない。本番配線の経路が書けない行は worker が理由を明記している（reviewer の重点確認対象になる。純粋な docs 変更等で経路が存在しない行は「該当なし + 理由」で受理できる）。
4. 検証台帳の最終エントリ SHA == 報告された HEAD SHA。
5. レビュー修正時: 対応表の全 must-fix / should 行に対応する evidence 行がある。

不受理の場合、main は理由を添えて worker へ差し戻す。main が代わりに修正・検証しない。

**証明 tier**: evidence の証明は、十分な最も低い tier を選ぶ。Tier A = ローカルで再現可能な決定的テスト（既定・merge gate）/ Tier B = 専用環境での検証（exact-image runner・実 DB 等。リポジトリにその仕組みがある場合のみ）/ Tier C = deploy 前 canary / Tier D = deploy 後観測（測定方法・fail-safe 上限・確認手順を宣言する）。環境・並行性・実プロセスに依存して Tier A で決定的にできない挙動（process 終端、大規模並行、実インフラ依存）は、targeted テスト 1 本 + Tier B〜D の宣言で受理できる。このとき safety / security に関わる機能は default-off で隔離してから後段 tier へ送る。flaky なテストを決定的にするための反復修正はしない（その時間は予算ゲートの対象になる）。

## Goal 設定

goal は次の形で設定する。`/goal` が使える環境では `/goal` として設定し、使えない環境では同じ内容を自分の完了条件として保持する。

```text
/goal /tmp/issue-pr-autopilot/<slug>.md を読み、その指示に従って issue 実装、worktree 作成、PR 作成、レビュー反復、検証、最終報告まで完了する。終了条件はファイル内の <completion_criteria> をすべて満たすこと。
```

goal ファイル（コンテキストノート）には少なくとも次を含める。

```text
<completion_criteria>
1. 対象 issue または作業説明の受け入れ条件を満たす実装がある（スコープ判定で stage 分割した場合は stage mapping の stage 1 subset）
2. ../ 配下の専用 worktree に、英語 prefix 付き commit が意味のある粒度で存在する
3. PR が open で、タイトルは英語、description は日本語で本 skill の形式に従っている
4. PR に round 1 のレビューコメント（妥当な指摘があった場合。main agent が妥当性判断後に投稿）と、レビューサマリー付きの最終コメント（APPROVED、または残指摘を明記した HANDOFF）がある
5. worker の evidence matrix が G3 の受理条件を満たし、main agent がレビューの妥当性を判断し、妥当な must-fix / should 指摘に対応済み、または予算ゲートに従って HANDOFF として記録済み
6. 検証台帳の最終エントリが「最終 HEAD の full validation 成功」で、SHA が HEAD と一致している
7. PR description の検証セクションが最終 HEAD と同期し、最新 HEAD の required checks が成功している（checks が無い場合は「なし」と記録）
8. 人間の判断待ち、未解決事項、検証不能事項、計測ログの cycle 表が PR と最終報告に記録されている
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

- **bundle 完全性の確認（fail-fast）**: この SKILL.md があるディレクトリからの相対で `../design/references/design-contract.md`・`../design/references/falsifier-rubric.md`・`references/review-rubric.md` を絶対パスへ解決し、存在を確認する。解決できない場合は bundle 破損として設計ゲート以降へ進まず、`make link` の再実行をユーザーに要求して停止する。解決した絶対パスはコンテキストノートに記録し、サブエージェント指示に埋め込む。
- issue URL または issue 番号がある場合は `gh issue view <number> --comments` を **1 回だけ**実行し、本文、受け入れ条件、議論、関連 PR を読む。
- 調査結果はコンテキストノート `/tmp/issue-pr-autopilot/<slug>.md`（goal ファイルと同一でよい）に書き出す。含めるもの: 作業内容、受け入れ条件、スコープ外、base branch、検証コマンド、リポジトリ規約の要点、reference の絶対パス、設計コンテキスト（後述）、対応表・検証台帳・計測ログの置き場所。以後、main agent とすべてのサブエージェントはこのノートを参照し、同じ調査を繰り返さない。
- 説明だけが渡された場合は、ノート内に「作業内容」「受け入れ条件」「スコープ外」を明文化する。
- base branch はユーザー指定を優先し、なければ remote default branch を使う。
- 検証コマンドは CLAUDE.md / AGENTS.md / README / Makefile / package.json / Gradle / CI 設定から推定する。分からない場合は最小の lint / test / build を選ぶ。
- `local.properties`、`.env`、認証ファイルなど、worktree で検証に必要な未追跡ファイルを確認する。秘密情報はコミットしない。

### 設計コンテキストの引き継ぎ

impl ↔ review の往復を減らす最大の要素は、設計判断を worker / reviewer に正確に引き継ぐことにある。コンテキストノートには「設計コンテキスト」セクションを必ず設け、設計（issue の「## 設計」またはこのセッションの設計議論）の決定事項を各 1〜2 行の一覧として転記し、設計ドキュメント（または issue の「## 設計」）へのパス・URL を添える。**設計本文の全文転記はしない**（ノートが肥大するとすべてのサブエージェントの全ターンが遅くなる）。worker / reviewer は詳細が必要なとき、参照先の該当セクションだけを読む。

情報源の優先順位は「このセッション内の設計議論・設計レビュー > issue 本文とコメント」とする。転記後、サブエージェントを spawn する前に「会話・issue で合意した設計判断のうちノートに載っていないものはないか」を確認する。どちらにも設計が無い場合は設計ゲート（後述）に従い、main agent の推定だけで設計コンテキストを埋めない（要件の言い換えにしかならない）。

## 設計ゲート（G2）

worker を spawn する前に、main agent が gate schema で設計を構造検査して分岐する。

- **単一レイヤーで自明な場合**（gate schema の layer 定義で判定。falsifier の客観条件リストに該当する変更は定義上この経路に入らない）: ノートの設計コンテキストに「設計: 不要と判断」と理由を明記して進む。この経路では条件付き matrix・反証パスを課さない。ただし worker の evidence matrix は必須のまま（受け入れ条件行だけの軽量 matrix で足りる）。
- **設計があるが旧形式・必須セクション欠落の場合**: designer サブエージェントに、既存の決定を保ったまま設計契約の形式へ補完させる（ゼロから再設計しない）。補完後に下の反証パスを通す。
- **設計が無く、複数レイヤーに跨る場合**: ユーザーに質問できる状況なら、質問ツールで「(a) 設計サブエージェントを走らせてから実装（推奨）/ (b) 設計なしで進める / (c) 中断して設計セッションで行う（design skill が使える環境ではそれを使う）」を確認する。自走中で質問できない場合は (a) を選ぶ。

(a) の designer は次の形式で spawn する。

```text
<designer_instruction>
あなたは設計サブエージェントです。コードを変更せず、実装前の設計だけを行ってください。

<scope>
- コンテキストノート: /tmp/issue-pr-autopilot/<slug>.md（作業内容・受け入れ条件・スコープ外が書いてある。必読）
- 設計契約: <design-contract.md の絶対パス>（設計の形式と記入基準。必読）
- 対象リポジトリ: <main checkout の絶対パス>（読み取りのみ）
</scope>

<rules>
禁止: コード・ドキュメントの変更 / 自分のサブエージェントの spawn / issue 本文の再取得。

- 関連コードを読み、設計契約の「## 設計」形式で設計する。事実と仮定は正本（config / DB 保存値 / runtime 値 / 表示値）を分離し、確認方法の無い値を事実にしない。スコープ判定は客観 signal を根拠に書く。条件付きセクションは発動条件を判定し、非該当は宣言ルールに従う。
- 決定は「〜とする」の形で書く。high リスクかつ未検証の仮定は、まず自分でコード・保存状態・運用経路から検証を試み、残ったものを理由付きで列挙する（勝手に仮決めしない）。
- コンテキストノートのスコープ外に踏み込む設計をしない。
</rules>

<deliverables>
main agent には次だけを返してください。コード本文は返さないでください。
1. issue にそのまま投稿できる「## 設計」セクション全文
2. 変更予定ファイル map の要約と、設計が触れる範囲（layer 数 / safety / migration / security / consumer 数 / DB hot path の該当有無）
3. high リスク・未検証のまま残った前提の一覧。なければ「なし」
</deliverables>
</designer_instruction>
```

### 設計ゲート内の反証パス

designer の成果物を確定する前に反証する。

- main agent が deliverable 2 を gate schema の客観条件リストに照らして判定し、該当すれば clean context の falsifier を 1 体 spawn する（必須。designer 自身に「該当なし」と判断させない。迷ったら発動）。falsifier には設計セクション全文・`falsifier-rubric.md` の絶対パス・対象リポジトリ（読み取りのみ）だけを渡し、rubric の職掌 4 点を falsification_result 形式で返させる。該当しない場合は designer に rubric に従った自己反証を別ターンで依頼する。自己反証で blocking 反例が 1 件でも出た場合は独立反証に昇格し、修正後の解消確認も独立 falsifier が行う。
- falsification_result は designer に渡し、rubric の処置ルールに従って処置させ、blocking / non-blocking 区分とともに設計の「反証」セクションへ記録させる。**falsifier-rubric.md の基準で blocking と判定された反例は、designer 単独の「受容 + 理由」で閉じられない**: 設計を修正して falsifier に再確認させるか、人間判断が必要な場合は高リスク未検証前提プロトコルの停止分岐（issue へ質問投稿）に乗せる。
- blocking 反例がゼロになり、反証処置まで完了した設計を issue の「## 設計」セクションとして投稿してからノートに展開する。blocking が残る設計で worker を spawn しない。

### 高リスク未検証前提の 3 分岐（自走時）

designer / falsifier が high リスクかつ未検証の前提を返した場合、main agent は次で分岐する（対話中なら質問ツールで確定させる）。

1. 未確定事項が**実装方式・不可逆 migration・安全性・permission 境界のいずれかを左右する**場合: 実装へ進まず停止する。issue に「質問」「候補」「根拠」を日本語で投稿し、未解決事項として最終報告に記録して、人間の回答後に再開する。
2. **reversible かつ additive で、未確定判断を含まない stage を切り出せる**場合: スコープ判定の stage mapping と同じ形式で、その stage だけ進行する。
3. 未確定事項が**既存状態を維持するだけで変更挙動に影響しない**場合のみ: fail-safe 側の解釈（既存状態を変更しない・自動 reconcile しない側）を仮決めとして採用し、設計に（高リスク・要人間確認）を付けて進行する。マークは reviewer round 1 の必須反証対象とし、PR の「人間に確認してほしいこと」へ転記する。

### スコープ判定と stage 分割

設計のスコープ判定が「1 worker / 1 reviewer で網羅不能」の場合の自走時の既定動作: **第 1 stage のみ実装して PR 化し、残 stage は issue に分割提案コメントとして投稿する。** 元の受け入れ条件は変更せず保持し、ノートに stage mapping（各受け入れ条件 → stage 1 / 後続 stage / non-goal）を追加して stage 1 の subset を completion criteria に割り当てる。PR は `Closes #<issue>` を付けず `Refs #<issue>` とし、PR description・最終報告・計測ログに「stage 1 / N、残 stage は issue の分割提案コメント参照」を明記する。各 stage が単独で merge・deploy 可能かつ backward-compatible であることが分割の成立条件（満たさない分割案は designer に差し戻す）。各 stage には設計契約の stage 予算（変更ファイル・diff 行数・binding decision 数の目安）を適用し、予算を大きく超える stage は designer に再分割を検討させる。

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

## 検証の信頼チェーンと検証 tier

同じ環境・同じ worktree でテストを何度も叩き直すのはこの skill の主要な浪費源のため、検証結果は台帳で 1 回だけ共有し、検証は tier で行う。

- worker は検証を実行するたびに、検証台帳エントリ「コマンド / 結果 / 実行時 HEAD SHA / validation scope」を報告する。
- **検証 tier**: 初回実装完了 = full（フルの test / lint / build）/ レビュー修正 = compile + 修正対象と同根経路の targeted tests / rebase = conflict または PR 変更箇所に関連する base 差分がある場合は affected tests、なければ compile / 仮承認後の最終 HEAD = full 1 回（G5 の必須条件。レビュー round の途中で「今回で閉じたはず」と見込んで最終 full を先行実行しない）。中間 tier でも検証失敗のままの完了報告は不可。
- reviewer は build / test / lint を**再実行しない**。検証台帳を信頼し、コードだけをレビューする。ただしレビュー開始時に検証台帳最終 SHA と HEAD の一致を read-only 操作で照合する（G4）。
- 再検証を実行するのは修正を行った worker であり、main agent や reviewer ではない。
- **検証 lease**: heavy validation（Gradle / Docker / Testcontainers 等を使うもの）は同一マシンで同時 1 本に直列化する。lease 操作は各 agent が shell で即興実装せず、同梱の helper `scripts/validation-lease.sh`（本 SKILL.md と同ディレクトリ。main が絶対パスへ解決してノートに記録する）で検証コマンドを包んで実行する。helper は OS の advisory lock（flock）を使うため、取得・解放・クラッシュ時解放を kernel が保証し、stale 判定・owner 管理・強制解放は不要。helper が出力する lock 待ち時間は external wait として台帳に記録し、SLO 通知の 120 分には算入しない。lock 待ちが長い場合はユーザーへ通知する（時間を理由に他 run の lease を奪わない）。helper が使えない環境では mkdir ベースの lock で代替してよいが、orphan lock の強制削除は自動化せず人間に確認する。JVM 系は worktree ごとに `GRADLE_USER_HOME` を分離し、他 run の Gradle daemon を停止させない。同一マシンで並走させる autopilot は 2 run までにする（超える場合はユーザーに申告する）。

## 実装 worker への指示

main agent は実装 worker サブエージェントを明示的に spawn し、次の形式で依頼する。利用環境のサブエージェント機能に合わせて文言だけ調整してよい。レビュー指摘の修正も同じ worker（コンテキストを引き継げる環境では同一スレッドの継続、難しければ対応表を渡した再依頼）に任せる。

```text
<worker_instruction>
あなたは実装 worker です。main agent の代わりに、指定 worktree 内だけで issue を実装してください。

<scope>
- コンテキストノート: /tmp/issue-pr-autopilot/<slug>.md（必読。作業内容、受け入れ条件、スコープ外、検証コマンド、検証 tier が書いてある）
- worktree: <absolute path>
- branch: <branch>
- base: <base branch>
</scope>

<rules>
禁止: main checkout・他 worktree の変更 / 無関係なリファクタ・別 issue の先取り / 秘密情報の追加 / 自分のサブエージェントの spawn / issue 本文の再取得（gh issue view の再実行）/ GitHub PR 操作（PR の作成・description 編集は main agent の責務）/ 検証が失敗した状態での完了報告（解決できない場合は失敗理由を報告する）。

- まずコンテキストノートを読み、「設計コンテキスト」の設計・決定事項に従って実装する。簡略化や別アプローチの方が良いと考えた場合は、実装を進める前に理由付きで main agent に判断を仰ぐ（黙って別解にしない）。
- worktree の CLAUDE.md / AGENTS.md にノート未記載の規約があれば読んで従う。
- スコープ内差分は適切な粒度・英語 prefix 付きでコミットする。変更前後で `git status -sb --untracked-files=all` と `git diff` を確認し、意図したファイルだけ stage する。
- 検証はノートの検証 tier に従い、コマンドは 1 回の呼び出しにまとめ、並列実行しない。heavy validation はノート記載の lease helper（validation-lease.sh）で包んで実行し、helper が出力する lock 待ち時間を external wait として台帳に記録する。検証台帳エントリには validation scope を必ず記録する。
- 機能名・クラス名・コマンド名を追加・変更したら、影響するドキュメント（README / docs/ / KDoc）を同じ PR 内で更新し、変更した名前で docs/ と README を grep して誤りになった記述が残っていないことを確認する。ドキュメントは現在の仕様を現在形で書き、変更の経緯や将来の予定を書かない。
- 関数のシグネチャや呼び出し規約を変えたら、呼び出し元を grep で全件洗い出して追随する（テストコード含む）。
- 新しい安全機構・新機能には、手組みの入力だけで通る unit テストに頼らず、本番の配線経由で実際に発動することを確認するテストを含める。
- レビュー指摘（must-fix / should）の修正は、finding 単位でなく finding cluster 単位で行う: 根本原因を特定し、同じ根の経路を grep / call graph で列挙してから一括で修正する。
- push の直前に `git fetch origin <base-branch>` と `git rebase origin/<base-branch>` を実行する。conflict は自分で解消し、rebase 後は検証 tier（affected または compile）で再検証して台帳を更新する。
- 報告前にセルフレビューする: 受け入れ条件の充足 / 規約違反 / スコープ逸脱 / diff の最終確認 / コミット粒度 / ドキュメント影響（grep 確認済みか）/ evidence matrix の全行が埋まっているか。lint や規約レベルの問題はレビューに回さず、この段階で直す。
</rules>

<deliverables>
main agent には次の構造化レポートだけを返してください。diff 全文・ログ全文は返さないでください。
1. evidence matrix: 行 = 受け入れ条件・設計の不変条件・（修正時は）指摘の閉じる条件、列 = 条件 / 実装箇所 / production call path / 証明するテスト名 / 検証結果 + HEAD SHA
2. commit 一覧（SHA と message）と変更ファイル一覧の 1 行要約
3. 検証台帳: コマンド / 結果 / 実行時 HEAD SHA / validation scope
4. PR description 更新材料: 検証セクションの SHA・チェックリスト差分（初回は title / description 案）
5. 判断に迷った点、未解決事項、スコープ外にした点
</deliverables>
</worker_instruction>
```

### 受理ゲート（G3）

worker の完了報告（初回・修正とも）を受けたら、main agent は gate schema の受理条件で evidence matrix を構造検査し、`git log --oneline origin/<base-branch>..HEAD` と `git diff --stat` でスポットチェックする。受理条件を満たさない報告は、理由を添えて worker へ差し戻す（reviewer に回さない）。「全件修正済み」等の要約だけの報告は受理しない。main が自分で修正してはならない。

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

PR は原則 ready-for-review で作成する。ユーザーが draft を指定した場合だけ draft にする。stage 分割時は `Closes` でなく `Refs #<issue>` を使う。

PR description は日本語で、次の構成にする。

```markdown
## 関連 Issue

- Closes #<issue-number>（stage 分割時は Refs #<issue-number> と「stage 1 / N」）
- <関連する issue / PR があれば箇条書きで追加>

## 実装目的

<なぜこの変更が必要かを短く書く>

## 実装内容

- <ユーザーが把握すべき粒度の変更点を箇条書き>

## 検証

### エージェント検証済み

- [x] `<検証コマンド>`（HEAD: <short SHA> / scope: full 等）

### 人間に確認してほしいこと

- [ ] <実機確認、UI 目視、（高リスク・要人間確認）マークの前提、reviewer の unchecked 観点など。なければ「なし」>

### 人間レビューへの引き継ぎ（HANDOFF）

<HANDOFF 終了時のみ: 未解消の指摘を severity・閉じる条件付きで列挙する。APPROVED 終了ならこのセクションごと削除する>

## ドキュメント影響

<「あり（対象ファイルの列挙）」または「なし」を1行で書く>

## メモ

- <必要な場合のみ書く。不要ならこのセクションごと削除する>
```

**PR description の更新は main agent の責務。** worker が push で HEAD を動かすたびに返す更新材料（検証セクションの SHA・チェックリスト差分）を使って main が description を最新化し、G5 で HEAD との同期を照合する。

## Reviewer サブエージェントへの指示（round 1）

PR 作成後、main agent は実装 worker とは別の reviewer サブエージェントを spawn する。round 2 以降は同じ reviewer を継続する（後述）。

```text
<reviewer_instruction>
あなたは reviewer サブエージェントです。コードを編集せず、レビューだけを行ってください。

<target>
- PR: <PR URL>
- コンテキストノート: /tmp/issue-pr-autopilot/<slug>.md（受け入れ条件・スコープ・設計コンテキストが書いてある。必読）
- review rubric: <review-rubric.md の絶対パス>（round 1 の 2 パス手順・review point matrix・evidence 突合基準。必読。反証 5 ベクトルの定義は <falsifier-rubric.md の絶対パス>）
- worktree: <absolute path>
- 検証台帳: <コマンド / 結果 / HEAD SHA / validation scope>
- worker の evidence matrix: <転記>
</target>

<rules>
禁止: build / test / lint の実行（検証台帳を信頼する。SHA 照合は git rev-parse 等の read-only 操作のみ）/ issue 本文の再取得・設計ドキュメントのフル読み直し（コンテキストノートを使う）/ 自分のサブエージェントの spawn / コードの編集。

- 開始前に rubric の G4 チェック（検証台帳最終 SHA == HEAD、かつ validation scope が現在の phase の要求 tier を満たす）を行い、満たさなければレビューせず main に差し戻す。
- rubric に従い、pass 1（設計反証）と pass 2（実装レビュー。call graph 追跡と evidence 突合を含む）の 2 パスで round 1 を行う。
- 網羅性を簡潔さより優先する。最初の該当指摘で止まらず、該当する指摘をすべて列挙し切ってから返す（取捨選択は下流の main が行う。内部 round は最大 2 回のため、このラウンドが指摘を出し切る唯一の機会と考える）。
- must-fix は rubric の同根 sweep と**有限の閉じる条件**を必ず付ける: 確認済みの対象（call site / failure point / 出力先）を列挙した inventory と、各項目を証明する観測（テスト名またはコマンド）。「全〜」「〜など」の開いた表現だけの閉じる条件は不可。設計自体の欠陥は「設計欠陥」ラベル付き must-fix にする。
- 証拠が確定しない指摘も捨てずに `confidence: low` を明記して報告してよい（取捨選択は main の妥当性判断が行う）。他の箇所に影響すると主張する場合は、実際に影響を受けるコード箇所を特定して示す。
- 組み込みのコードレビュー機能（Codex の `/review` 等）が使える場合、round 1 の初手として base branch 比較で実行し、別レンズの洗い出しとして使う。最終的な指摘の取捨選択・severity 判定・投稿はこの指示に従う。
</rules>

<posting_protocol>
- GitHub には投稿しないでください。round 1 のレビューコメントは、main agent が全指摘の妥当性を判断した後に投稿します。結果は review_result 形式で main agent にだけ返してください。
- 各指摘に severity（rubric の基準に従う）と file:line を付けてください。
- 根拠のない好み、スコープ外要求、実装方針の押し付けは避けてください。
</posting_protocol>
</reviewer_instruction>
```

reviewer は main agent に次だけ返す。

```text
<review_result>
- cycle / round: <C / N>
- result: APPROVABLE_PENDING_FULL / COMMENTS
- must-fix: <count>（うち設計欠陥 <count>）/ should: <count> / nit: <count>
- last_reviewed_sha: <レビュー時点の HEAD SHA>
- findings: <各指摘の要約（severity / file:line / 要旨 / must-fix は閉じる条件と同根 call site 一覧も含める）>
- review_point_matrix: <rubric の形式。全 review point の checked / unchecked（unchecked は理由付き）>
</review_result>
```

reviewer の unchecked に挙がった観点は、main agent が PR description の「人間に確認してほしいこと」に転記する。**safety・migration・security に属する unchecked が残る場合、reviewer は仮承認を返さない**（閉じ方は G5 の 3 ルート）。

reviewer が「1 reviewer では網羅不能」と申告した場合のみ、main は (a) PR 分割の要求、または (b) 設計反証専任と実装レビュー専任の 2 reviewer への分割を行う。無条件の複数 reviewer 化はしない。

## レビュー反復（round 2 以降）

main agent は review_result を読み、各指摘を対応表（指摘 → 閉じる条件 → 対応状況）に登録して分類する。

- 妥当な must-fix / should: worker に修正させ、commit と push をさせる。**設計欠陥ラベル付きは worker でなく designer に設計修正を依頼し、issue の「## 設計」とノートを更新してから worker に反映させる**（同一 cycle 内の round として数える）。designer には設計 delta・falsifier 再確認の要否・**修正規模見積り（diff 行数・新規コンポーネント数）**を返させる。見積りが予算ゲートの構造条件 3（新 layer / 新規サブシステム）または scope-growth シグナルに触れる場合は、main が adjudication 例外（役割規律参照）で指摘の妥当性を検証した上で、実装せず stage-out を既定とする: 該当機能を default-off / feature flag で隔離し、対策を follow-up issue の提案コメントとして投稿する。
- 妥当な nit: 対応が安ければ worker にまとめて直させる。対応しない場合は理由を対応表に記録する。
- 不妥当、スコープ外、既存仕様と矛盾: 対応しない理由を対応表に記録する。
- 仕様判断が必要: issue または PR に「質問」「仮決め」「根拠」を日本語で書き、PR description の「人間に確認してほしいこと」にも残す。

分類の完了後、round 1 の妥当と判断した指摘（must-fix / should / 対応する nit）を main が GitHub PR へ日本語の 1 コメント（`## レビュー (cycle <C> / ラウンド 1)`、severity と file:line 付き）として投稿する。不妥当と判断した指摘は投稿せず、理由を対応表に記録する。妥当な指摘がゼロの場合は round 1 コメントを投稿しない。指摘ごとの個別返信コメントは投稿しない。対応内容は最終コメントの対応表にまとめて記録する。

修正後の再レビューは次のルールで行う。

- worker の修正報告を G3 で受理してから（対応表の全 must-fix / should に evidence 行があること）、同じ reviewer を継続する。コンテキストを引き継げる環境では同一サブエージェントに追加依頼し、難しければ前回の findings と対応表を添えて再依頼する。
- 再レビュー開始前に G4（検証台帳最終 SHA == HEAD、かつ validation scope が phase の要求 tier を満たす）を照合する。満たさなければ先に worker に検証させる。
- 再レビューの範囲は `git diff <last_reviewed_sha>..HEAD` の変更行と、前回指摘の対応確認。対応確認は各 must-fix の inventory ID 単位で **CLOSED / PARTIAL（未充足 ID を列挙）/ NEW** で判定し、**同一指摘の要求を round 2 で拡張しない**（inventory に無い経路を後から見つけた場合は、reopen ではなく NEW の新規指摘として扱う）。「round 1 網羅漏れ」ラベル付きの新規指摘は round 2 までで打ち切り、以降に見つかる指摘は人間レビューへの引き継ぎに回す。修正コミットが新規に持ち込んだ問題（rubric の修正コミット固有欠陥クラス）は round に関わらず指摘対象。無関係な未変更コードの再レビューは行わない。
- **設計欠陥の修正を含む再レビューでは、pass 1 を改訂設計に対して再実行する。** main は rereview_request に改訂後の決定事項（ノートの設計コンテキストの差分）を明示し、reviewer は改訂箇所への反証 5 ベクトルと、改訂された invariant・挙動の影響を受ける既存 call site の再確認を必須で行う（diff に現れない箇所でも、改訂設計が前提を変えた範囲は再確認の対象）。無関係な全コードの再レビューはしない。
- 中間ラウンドの結果は GitHub に投稿せず、review_result 形式で main agent に返させる。

```text
<rereview_request>
- cycle / round: <C / N + 1>
- 対応表: <指摘ごとの対応状況。修正済み（short SHA）/ 対応せず + 理由>
- worker evidence matrix: <修正分の転記>
- 設計改訂: <設計欠陥を修正した場合、改訂後の決定事項と影響範囲。なければ「なし」>
- レビュー範囲: git diff <last_reviewed_sha>..HEAD の変更行 + 前回指摘の対応確認 + 修正コミット固有欠陥クラス。設計改訂がある場合は、改訂箇所への pass 1（反証 5 ベクトル）と影響を受ける invariant・call site の再確認を含める
- ルール: 前回指摘は inventory ID 単位で CLOSED / PARTIAL / NEW を判定し、同一指摘の要求を拡張しない。「round 1 網羅漏れ」の新規指摘はこの round まで。無関係な未変更コードの再レビューは不可。build / test は実行しない。結果は GitHub に投稿せず review_result 形式で返す。
</rereview_request>
```

## 終了状態（APPROVED / HANDOFF）と最終コメント

この skill の終了状態は 2 つあり、混同しない。

- **APPROVED**: G5 の全条件を満たした状態。妥当な must-fix / should と高リスク unchecked がゼロ。
- **HANDOFF（人間レビューへの引き継ぎ）**: 予算ゲートの発動、または G5 を満たせない場合の内部処理の終了。**承認ではなく、G5 通過とも扱わない。** 残指摘・unchecked・cycle 表を PR に記録し、判断を人間に引き渡す。

仮承認フロー: must-fix / should がゼロになったら reviewer は**仮承認**（APPROVABLE_PENDING_FULL）を返す。**nit だけが残っている場合も、残存事項として注記した上で仮承認を返す。** 仮承認の時点では検証台帳は targeted tier で足りる（コードレベルの closure 確認に full を要求しない）。仮承認後に worker が最終 HEAD の full validation を 1 回だけ実行し、成功かつ SHA 不変なら G5 照合に進む。full で失敗が出た場合のみ修正 + 再検証し、diff が変わったら reviewer に変更行だけ確認させる。HANDOFF の場合も最終 full validation を 1 回試行する（失敗したらその事実も残指摘に記録する）。

main agent は APPROVED コメントの投稿前に次を照合する（G5）。

1. review_point_matrix に safety・migration・security の unchecked が残っていない。この unchecked は人間確認事項への転記（可視化）だけでは閉じない。閉じる方法は 2 つ: (1) 人間の回答・観測可能な証拠で reviewer が checked と再判定する（自走中は issue へ質問を 1 回投稿する。回答を無期限には待たない） (2) 該当範囲を分割して本 PR のスコープから除外する。default-off / feature flag による隔離は checked にせず **isolated_unverified**（rubric 参照）として扱い、rubric の 3 条件を reviewer が確認した場合に限り APPROVED を妨げない（人間確認事項への転記必須）。どれも成立しない場合、終了状態は HANDOFF になる。
2. 検証台帳の最終エントリが「最終 HEAD の full validation 成功」である（不一致・scope 不足なら worker に最終検証を 1 回実行させる）。
3. PR description の検証セクションが最終 HEAD と同期している（main が worker の更新材料で最新化する）。
4. 最新 HEAD の required checks（GitHub CI）が完了して成功している（checks が無いリポジトリは「なし」と記録する）。pending 中は最終コメントを投稿せず `gh pr checks --watch` 1 回で待つ。failure は APPROVED 前に CI cycle として処理し、修正後の最新 HEAD で local full validation と required checks の両方を再確認する。外部承認や手動実行が必要な check を除外する場合は、その旨を人間確認事項として明示する。

成立したら次の形式の最終コメントを PR に投稿する。HANDOFF の場合は見出しを「## レビュー結果: HANDOFF（人間レビューへの引き継ぎ。承認ではない）」に変え、残指摘（severity / 閉じる条件 / 理由 = 発動した予算ゲートまたは満たせなかった G5 条件）の表を追加する。

```markdown
## レビュー結果: APPROVED

### サマリー

- cycle 表: | cycle | トリガー | rounds | must-fix / should | finding origin | 時間 |（cycle ごとに 1 行）
- 指摘合計: must-fix <X>（うち設計欠陥 <D>）/ should <Y> / nit <Z>
- 最終検証: `<コマンド>` 成功（HEAD: <short SHA> / scope: full）

### 指摘と対応

| # | 指摘（要約） | severity | 対応 |
|---|---|---|---|
| 1 | <要約> | must-fix | 修正済み（<short SHA>） |
| 2 | <要約> | nit | 対応せず: <短い理由> |

### 残存事項

- <未対応 nit の注記、仕様判断待ち、（高リスク・要人間確認）の前提。なければ「なし」>
```

指摘がひとつもなかった場合は「指摘と対応」の表を省略してよい。

## cycle / round の定義と計測ログ

- **round**: 同一 cycle 内の reviewer 往復の回数。
- **review cycle**: 次のいずれかで新 cycle を開始し、round を 1 に戻す。
  - 外部レビューバッチの受領（常に新 cycle）。
  - CI failure のうち、新しい欠陥クラスの発見または PR 差分の変更を要するもの（flaky の再実行や metadata のみの修正で閉じるものは同 cycle 内で処理する）。
  - rebase のうち、PR 変更箇所・security contract・schema/API に実質的な重なりのある base 差分の統合（重なりのない rebase は同 cycle）。
  - docs・metadata だけで閉じる対応は cycle を増やさない。
- **cycle 判定の validator**: 内部レビューの再往復（worker 修正 → 同一 reviewer の再レビュー）は、上記トリガーに該当しない限り常に**同一 cycle の次 round** として数える。routine な再レビューを新 cycle として扱うと、round 上限（最大 2）と incomplete closure の集計が無効になるため、新 cycle の開始時は該当トリガーを計測ログに必ず記録する（トリガーを書けない cycle 開始は誤分類）。
- cycle 開始時に reviewer へ「新 cycle・トリガー・レビュー範囲」を明示して依頼する。外部指摘は鵜呑みにせず reviewer に再監査させる。
- **計測ログ**: main agent は round ごとに即時記録する（review 返却時と worker 修正完了時。最終確定まで書き溜めない）。コンテキストノートの専用セクションに cycle ごとに 1 行で記録する: cycle 番号 / トリガー / round 数 / must-fix・should 件数 / finding origin（internal-r1 / internal-r2+ / external / CI）/ fix-induced regression 件数 / incomplete closure（同一指摘の再往復）件数 / 発動した予算ゲート / 時間。時間は 4 区分: wall-clock elapsed（cycle 開始から終了までの実時間）/ cumulative agent compute time（並列実行を含む全サブエージェント実行時間の合計）/ critical-path agent elapsed（直列依存の経路上にあるエージェント実行時間。算出困難なら unknown とし、推測値を確定値として記録しない）/ external wait（ユーザー・外部レビュー・CI の待ち時間）。cycle 表は最終コメントと最終報告に転記するほか、**run を中断・引き継ぎする場合もその時点の表を PR コメントへ投稿する**（/tmp は揮発のため PR コメントが永続記録になる）。

## 最終報告

完了時はユーザーに次を簡潔に報告する。

- PR URL
- branch / worktree
- commit 範囲
- cycle 表（計測ログの転記）と指摘の内訳
- 検証台帳の最終エントリ（コマンド / 結果 / SHA / scope）
- 人間の判断待ち、未解決事項、検証不能事項（stage 分割時は残 stage）

worktree は削除せず残す。削除や merge はユーザーから明示指示がある場合だけ行う。merge を指示された場合は mergeability を確認してから 1 回だけ実行する。

skill 完了後に同じ PR への追加対応（外部レビュー指摘、CI 失敗等）を依頼された場合も、main agent の役割規律と cycle 定義を維持する。外部レビューは新しい cycle として開始し、指摘の再監査 → G3 受理 → 再レビュー → G5 の同じプロトコルを回す。ビルド・テスト・ロジック変更を伴う対応は worker の継続または再 spawn で委任し、検証不要な軽微修正だけ main agent が直接行ってよい。

## 環境別ヒント

コア原則: 役割ごとにモデルティアと effort を分ける。1〜2 パスの品質で決まる役割（反証・round 1 レビュー）に最上位ティアの高 effort を使い、多ターンの実装 worker は速度と消費を優先する。現行世代（Fable 5 / GPT-5.6）は手順の細目列挙より「ゴール + 制約 + 完了条件」で最も性能が出るため、サブエージェント指示はテンプレートの必要部分だけを埋め、ノートにある情報を重複転記しない。reviewer の round 1 網羅方針は現行モデルのレビュー特性（確度の低い指摘も報告させ、フィルタは下流で行うほうが recall が高い）に合わせた設計であり、reviewer 側で保守的に間引かせない。round 2 以降は同じ reviewer を継続して、前回指摘の対応確認と新規 diff だけに入力を絞る。実行中のサブエージェントの進捗は、メッセージ送信ではなく worker worktree の読み取り専用観察（git log / status / diff）で確認し、実装が長時間になることをハングと判断しない。diff・コンテキストノート・既存コードを長く読む役割には最軽量ティアを使わない。サブエージェントを spawn・継続するたびに、割り当てたモデル名（effort を指定できる環境では effort も）を進捗報告に明示する。サブエージェントは数を増やすより、1 回あたりの入力を絞る方が効く。

### Claude Code

- モデルはサブエージェント呼び出し時の `model` パラメータで役割別に指定する。推奨割当: 実装 worker = Sonnet 5、designer / falsifier / reviewer = Fable 5（security・情報露出が主対象の変更は reviewer = Opus 4.8。Fable 5 が security 分析で refusal・分析劣化を起こした場合も Opus 4.8 で再依頼する）。Haiku 4.5 は機械的な補助作業のみ。falsifier は clean context のため新規 spawn する。
- 役割別に effort を固定したい場合は `.claude/agents/` の role 別エージェント定義（frontmatter）で指定する。round 2 以降は同一 reviewer を SendMessage で継続し、入力を前回 findings と `git diff <last_reviewed_sha>..HEAD` に絞る。
- main agent は role 別 reference（design-contract.md / falsifier-rubric.md / review-rubric.md）を読まず、絶対パスへ解決してサブエージェント指示に埋め込む。gate schema は本 SKILL.md 内にあるため追加読み込みなしで G2 / G3 を判定できる。
- 完了したサブエージェントは SendMessage で文脈を保ったまま再開できる。worker / reviewer の継続はこれを使い、再 spawn しない。
- サブエージェントは既定でバックグラウンド実行される。worker の実装中に main agent が PR body の準備などを進めてよい。
- `/code-review` が使える場合、reviewer はこれを指摘の洗い出しに使える。

### Codex

- `~/.codex/agents/` の TOML でエージェント毎に `model` / `model_reasoning_effort` を定義できる。並列上限は `agents.max_threads`（既定 6）。
- 推奨割当: main agent = `gpt-5.6-sol`（`model_reasoning_effort = "medium"`、`plan_mode_reasoning_effort = "high"`）、実装 worker = `gpt-5.6-sol`（`"medium"`。トークン効率が高く、`gpt-5.6-terra` の `"high"` と同等以下のステップ数・出力量でより高い精度が出るため、実装の速度優先と両立する）、designer = `gpt-5.6-sol`（`"high"`。質問・修正の往復が入る役割のため）、falsifier / reviewer = `gpt-5.6-sol`（`"xhigh"`。GPT-5.6 世代は `xhigh` を難問に限定し日常は `medium` が推奨のため、`xhigh` は 1 パスの反証品質で決まるこの 2 役割に限る）。
- 本 bundle の運用規約として、Codex では main もその run で必要になった reference だけを読んでよい（実行環境が必須 reference の読み込みを要求する場合はそれに従う）。設計ゲートを通らない run では design-contract.md を読まない。gate schema は本 SKILL.md 内のため常に追加読み込みなし。
- round 2 以降も同一 reviewer thread と `"xhigh"` を維持する。継続依頼では前回の findings、対応表、`git diff <last_reviewed_sha>..HEAD` だけを渡し、全体を再読させない。spawn 後の thread に対して effort を変更できると仮定しない。
- `gpt-5.6-luna` は primary role に割り当てない。context をほとんど積まない機械的な補助作業に限る。
- `model_reasoning_effort` の `max` / `ultra` は使わない。`max` は `xhigh` に対する消費増が大きく、`ultra` はモデル内部の subagent 委任が本 skill のオーケストレーションと二重になる。
- clean context が必要な reviewer / falsifier は fork なしで spawn する（確認済みの指定は `spawn_agent` の `fork_turns = "none"`）。直近の会話を引き継ぐ worker は fork を許す設定にする。fork 制御のパラメータ名・値域は世代で変わり得るため、実行環境で確認してから使う。`agent_type` と併用できる。
- **サブエージェント操作の tool 名は世代で異なる。固有名を仮定せず、実行環境で公開されている collaboration tool を最初に確認して分岐する**: hosted surface では `spawn_agent` / `send_message` / `followup_task` / `wait_agent` / `interrupt_agent` / `list_agents` の 6 操作を使い、継続は `followup_task`、状態確認は `wait_agent` / `list_agents` で行う（終了 thread の明示 close は存在しないため要求しない）。local legacy surface では `send_input` / `resume_agent` / `close_agent` が実在する場合のみ使い、読み終えた終了済み subagent は `close_agent` で閉じる（spawn スロットのリーク対策）。
- reviewer の継続は同一サブエージェントスレッドへの追加依頼（hosted は `followup_task`）で行う。
- blocking wait は 1 回を原則 60 秒以下にし、短い wait と worktree 観察を繰り返す（長い timeout の 1 回待ちはユーザーから長時間停止に見える）。wait のタイムアウトは「まだ Running」という意味でしかなく、ハングの根拠にしない。実装が長時間になるのは正常。
- 進捗確認は Running 中の subagent へのメッセージではなく、worker の worktree の読み取り専用観察で行う: `git -C <worktree> log --oneline`、`git -C <worktree> status -sb`、`git -C <worktree> diff --stat`。worker はコミット粒度の規律に従うため、log がそのまま進捗ログになる。
- Running 中の worker にメッセージで進捗を尋ねない。メッセージは worker に user 入力として注入され、返信は worker のターン終了時にしか届かない。interrupt（`interrupt_agent` / interrupt 付き `send_input`）は実行中ターンを中断させ、作業を失わせる。
- 停滞判定は経過時間ではなく worktree の変化で行う。間隔を空けた複数回の観察で log・status・diff に変化がなく wait も Running のままの場合に限り、interrupt なしのメッセージを 1 回だけ送る。それでも次の wait とその後の観察で変化がない場合のみ再 spawn する。main agent が実装を引き継がない。
- 組み込みの `/review` は read-only の専用レビュアーで、対象リポジトリの AGENTS.md に「Review guidelines」節を書くと指摘基準を調整できる。
- 同一 GitHub アカウントでは自分の PR に `gh pr review --approve` できないため、レビューは `gh pr comment` ベースのプロトコルで代替する。
