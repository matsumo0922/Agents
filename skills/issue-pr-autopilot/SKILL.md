---
name: issue-pr-autopilot
description: "GitHub issue や作業説明を起点に、OpenSpec の propose→apply を専用 worktree 内で駆動し、反証ゲート・レビューループ・収束判定を経て、人間が短時間で merge 判断できる PR（単一 PR または GitHub Stack）を自走で作る配送シェル。Use when the user wants to turn an issue or task description into a reviewed pull request with autonomous subagents and worktrees, issue を PR にして, autopilot で実装して, 自走で PR まで進めて."
---

# Issue PR Autopilot

## 目的

issue または作業説明から、「証拠と未確認事項が整理され、人間が短時間で merge 判断できる PR」を最短で出す。品質保証の最終責任は人間の PR レビューにあり、内部ループで完璧を目指さない。速度は品質と同格の要件であり、最少の有用なループで終了条件を満たしたらそれ以上磨かない。ただしループ削減を、正確性と必須の証拠より優先しない。

OpenSpec との役割分担として、成果物の形式（proposal.md / delta spec / design.md / tasks.md）、進捗の外部記録、仕様の永続化（`openspec/specs/`）は OpenSpec が担う。本スキルはその propose→apply を駆動する配送シェルとして、worktree 管理、反証ゲート、配送単位の決定、PR 作成、レビューループ、収束判定、終了状態（APPROVED / HANDOFF）を担う。

### 非目標

- 完璧な PR を作ること（作らないこと自体を目的の一部とする）
- 受け入れ条件にも設計決定にも紐付かない改善（リファクタ、hardening、nit 対応）
- merge すること（人間の専権）
- main checkout の変更

### 正本の二層定義

- 契約の正本は issue の受け入れ条件、実行時の検証単位は delta spec の Scenario（GIVEN/WHEN/THEN）とする
- delta spec の各 Requirement は issue の受け入れ条件への trace を持つ。両者の食い違いを発見したら停止して質問する

## 開始条件と事前チェック

- 入力：issue 番号 / issue URL / 短い作業説明のいずれか。git リポジトリで gh 認証が通っていること
- issue 本文の取得は run を通じて 1 回だけ（`gh issue view <n> --comments`）とし、取得結果を run 全体で使い回す（再取得のたびに契約を再解釈すると目的がぶれるため）
- base branch を確認する
- OpenSpec 導入の 3 分岐：
  - 導入済み（`openspec/` がある）→ そのまま進む
  - 未導入で対話中 → `openspec init` するかユーザーに質問する
  - 未導入で自走中 → 停止して issue へ質問するのが既定。自明な単一レイヤー変更に限り、OpenSpec 成果物なしの軽量フォールバック（設計は PR description に直書き）で進んでよく、その旨を最終報告に明記する。フォールバック時の読み替え：アンカー先 = issue の受け入れ条件 ∪ 非退行 invariant、G1（`openspec validate`）は不適用、G2 の証明単位 = 受け入れ条件
  - いずれの場合も、ユーザーの確認なしに `openspec init` を実行しない（commit 対象になる規約の決定はユーザー専権）

設計が必要な規模の変更では、blocking 反例が残る設計のまま実装に入らない（反証ゲートを参照）。

## 配送単位

単一の intent を持つ issue では「1 Issue = 1 OpenSpec change = 1 proposal」を原則とする。複数の依存 PR が必要でも PR ごとに change を分割しない。独立して archive できる別 intent は、同じ change に足さず子 issue・別 change・別 run に分ける。issue が複数の独立 intent を含むことに気づいたら、対話中は分割を提案し、自走中は停止して issue へ質問する。

配送形態は 2 つ。propose 完了時に main が選び、選択と理由を proposal.md に記録する。

- **単一 PR（既定）**：change の全成果物と実装を 1 つの PR で出す。単一 PR で十分な変更へ PR-proposal / PR-archive を強制しない
- **Stack**：独立してレビューできる複数の依存 PR に分ける価値がある場合のみ。1 つの change の tasks を Stack の各実装 PR へ割り当てる

Stack を選ぶ判定は次のとおり。PR 数や行数を目的に分割しない。

- 各実装 PR が、独立してレビューでき、可能な限り production path へ接続された縦切りになること
- 並列で依存しない作業は linear Stack に含めない（別 intent として切り出す）

Stack の構成（下段から）：

```text
PR-proposal   … issue 全体の proposal / delta spec / design / tasks（最下段）
PR-1 .. PR-N  … 担当 tasks subset の実装・テスト・進捗更新
PR-archive    … main spec への同期と change の archive（最上段。G1〜G4 成立後にのみ作り、その HEAD で最終 full validation を行う）
```

- **trace**：各実装 PR は同じ change の Scenario / tasks の subset に trace する。tasks.md の各 task に担当 PR（branch 名）を記し、各実装 PR の description は担当 subset を列挙する。OpenSpec artifacts の内容を PR description に再説明しない（重複した説明は片方が腐る）。PR description の固有の責務は、担当 subset の列挙、検証結果、人間確認事項とする
- **生成タイミング**：PR-proposal は実装開始前に最下段として作る。反証ゲートに該当する提案ではその通過後、該当しない提案では propose の最初の commit 後とする。実装 PR は担当 subset の実装完了ごとに上段へ積む。PR-archive は全実装 PR の収束（G1〜G4 成立）後にのみ作り、その HEAD で最終 full validation を行う。実装開始の条件は反証ゲートの通過とし、PR-proposal の人間承認を待たずに実装 PR を積んでよい（人間の承認は merge 時に一括で行われる）
- **merge の方式**：Stack の merge には `gh pr merge` は使えず、人間が `gh stack merge --yes` で下段から順に一括 merge する（`gh stack merge <pr番号> --yes` で途中までの merge も可能）。最終報告にこのコマンドを明記する。base branch が merge queue を使う repository では、Stack は queue へ一括投入されるが queue の処理順で別グループに分かれて landing しうる
- **landing 順の不変条件**：archive が実装より先に landing してはならない。partial merge や merge queue の分割 landing で実装だけが先に landing した場合は、change が active のまま残ることを許容する（回収は archive 節を参照）。queue 投入済み（`gh stack view --json` で `isQueued`）の branch は push / rebase の対象外になるため、queue 処理中は Stack の変異を行わず landing の完了を待つ

### Stack 操作の規約

- Stack の作成・変異（`init` / `add` / `checkout` / `push` / `submit` / `rebase` / `sync` / `unstack`）は main 専権とする。worker には行わせない（Stack は branch を跨ぐ共有状態で、並行変異は branch 対応と検証記録を壊すため）
- `gh stack` コマンドは gh-stack スキル（本スキルの前提。Agent rules と exit code 表を正とする）に従い非対話で実行する（`submit --auto`、`view --json`、branch 名の明示。プロンプトや TUI を誘発する形は使わない）。初回の `gh stack` 実行前に `git config rerere.enabled true` と `git config remote.pushDefault origin` を設定する（未設定だと `init` が確認プロンプトで hang しうる）
- Stack は worktree の branch を最下段として組む。propose 完了時に Stack を選んだら、worktree の branch を PR-proposal 用として `gh stack init <branch名>` で adopt し、実装 branch は `gh stack add <branch名>` で上段に積む（`add` は最上段の branch からのみ実行できるため、下段での作業後は `gh stack top` で最上段へ移動してから積む）。branch 名は通常の branch 命名に従い、layer の担当が分かる名前にする
- `gh stack submit --auto` は draft PR を作るため、レビュー可能にする段階で `--open` を付けるか `gh pr ready` で ready 化する（draft のままでは `gh stack merge` の事前チェックを通らない）。PR title / body は自動生成のため、submit 後に各 PR を `gh pr edit` で本リポジトリの規約（title 英語 / description 日本語）へ更新する
- 下段の変更で proposal / design / delta spec が変わった場合は、該当する下段 branch を修正して `gh stack rebase --upstack` で上段を追随させる。PR-archive が既にあれば archive 内容を再生成する。rebase 後の再検証は検証 tier の規則に従う

### fallback（Stack が使えない場合）

GitHub Stacked PRs は repository ごとの有効化が必要で、無効な repository では `gh stack submit` が exit code 9 を返す。exit 9 の時点で branch の push と連鎖 base の通常 PR（PR-proposal の base = base branch、PR-1 の base = PR-proposal の branch、…）の作成までは完了しており、失敗しているのは Stack としてのグルーピングだけである。fallback ではこの作成済み PR をそのまま使い、PR を作り直さない。配送単位（1 Issue = 1 change = 1 proposal）と PR 構成は変えない。Stack 機能は差分表示と merge 支援であり、配送単位の前提ではない。fallback 時は `gh stack merge` が使えないため、下段から順に人間が merge する必要があることを各 PR description に明記する。

## エージェント構成

main が文脈を全部持つリード役として、propose、配送単位の決定、実装、裁定、収束判定を自分で行う。clean context の隔離は敵対的役割だけに適用する。

- **falsifier / reviewer**：clean context。書き手と実装者の弁明を渡さない
- **worker**：「長大な実装」と「レビュー修正ラウンド（裁定者と修正者の分離）」でのみ fresh spawn し、main が書いた濃い brief を渡す
- **architect**：propose は main が自分で行うのが既定。設計作業を委任する場合のみ spawn する

サブエージェント間の受け渡しは要約と参照（パス、SHA、URL）で行い、ネストさせない（中継のたびに文脈が劣化コピーになるため）。spawn のたびに割り当てモデル名を進捗報告に明示する。

### モデル割当

main は常にセッションのモデル。subagent は実行環境ごとに次表を既定とする。

| 役割                | Claude Code（Claude のみ） | Codex（GPT のみ）    | Claude Code（クロスモデル） |
|---------------------|----------------------------|----------------------|-----------------------------|
| architect（委任時） | Opus 5 / high              | gpt-5.6-sol / medium | Opus 5 / high               |
| falsifier           | Opus 5 / high              | gpt-5.6-sol / high   | gpt-5.6-sol / high          |
| worker              | Sonnet 5 / high            | gpt-5.6-sol / medium | gpt-5.6-sol / medium        |
| reviewer            | Opus 5 / high              | gpt-5.6-sol / high   | Opus 5 / high               |

- **呼び出し方**：Claude モデルは Agent tool の `model` 指定（`opus` / `sonnet` / `fable`）で呼び、effort はセッション既定を継承する。GPT モデルは `~/.claude/agents/` の agent 定義（`gpt-medium` / `gpt-high` / `gpt-xhigh`）で呼び、effort は定義の frontmatter が決める
- **昇格**：反証ゲートの高リスク基準（safety / security / migration / cross-layer / 複数 consumer / DB hot path）に触れる対象への falsifier / reviewer は、main が spawn 前に 1 段上へ昇格する。Opus 5 → Fable 5（effort はセッション既定）、gpt-5.6-sol / high → gpt-5.6-sol / xhigh
- **fallback**：GPT の agent 定義が無い環境（プロキシを経由しない直結環境など）では、クロスモデル列を使わず「Claude のみ」列で全役割を賄う。Claude subagent が無い環境では「Codex」列で賄う

## 進め方

### 1. 割当を確認

architect（委任時）, falsifier, worker, reviewer のそれぞれについて、使用するモデル名と effort を表にして明示する。反証ゲートの高リスク基準に該当し、昇格を行う際はその旨を明示し、質問 tool で昇格を行なって良いかユーザーに確認を取る。

進捗報告は開始時、phase 完了時、重要な発見、方針変更、block 発生時だけ行う。コマンド単位の予告や、既に明らかな次工程の実況は行わない。最終報告は結果から始め、必要な詳細を後に置く。

### 2. worktree と propose

- 兄弟ディレクトリに worktree + branch を作る。propose より先に行い、main checkout を汚さない。検証に必要な未追跡ファイル（`local.properties` / `.env` 等）だけをコピーし、.gitignore に守られていることを確認する
- merge 済みで未 archive の change が残っていれば、回収専用の worktree + branch を別に作って回収する（main checkout は変更しない）。回収 PR は `openspec archive <name> --yes` の機械的な差分だけを載せた `chore:` PR とし、この run のレビューループと G ゲートの対象にはしない（archive 節を参照）。回収差分をこの run の feature PR に混ぜない
- `openspec/changes/<name>/` が既にあればそれを使う。無ければ worktree 内で propose する。`openspec new change` で作成し、`openspec status --change <name> --json` と `openspec instructions <artifact> --change <name> --json` に従って 4 点セット（proposal.md / delta spec / design.md / tasks.md）を書き、`openspec validate <name>` を通してから最初の commit を打つ
- 提案は受け入れ条件を満たす最小のものを既定とする。受け入れ条件が複数の解釈を許す場合は最小の解釈を採り、より広い解釈は提案に含めず質問または follow-up として残す。提案の拡張は、反証・レビュー・検証のいずれかが実際に失敗を示した場合にのみ行い、「あった方が良い」「将来必要になる」を理由に先回りしない
- 設計上の各決定には帰属タグ（ユーザー確認済み / agent 仮決め / 高リスク・要人間確認）を付ける。高リスク未検証前提の 3 分岐プロトコルと質問の作法は falsify スキルの規約に従う
- propose 完了時に配送単位（単一 PR / Stack）を決め、Stack なら tasks.md に担当 PR の割当を書く。falsify の stage-out で対策を分離する場合、分離先を 2 種に区別する。(1) 同一 intent 内の後続実装単位 → 同じ change の tasks として後続の実装 PR（Stack の上段）に割り当てる。(2) 独立して archive できる別 intent → 子 issue・別 change に分け、issue にコメントで残す。受け入れ条件との対応（この PR / 後続 PR / 別 issue / non-goal）を proposal.md に記録する

### 3. 反証ゲート

safety / security / migration / cross-layer / 複数 consumer / DB hot path に触れる提案は、falsify スキルの独立 falsifier に proposal + delta spec を反証させる。blocking 反例が解消される（falsify の処置 4 ルートのいずれかで閉じる）まで実装に入らない。

Stack 配送では、実装開始前に PR-proposal を最下段として作る（Stack 操作の規約に従い submit → `gh pr edit`）。反証ゲートに該当する提案ではその通過後に、該当しない提案ではこの節をスキップして propose の最初の commit 後に作る。

### 4. 実装（apply）

apply の意味論は本スキルが定義する（OpenSpec のスラッシュコマンド実体に依存せず、CLI と change 名だけで完結させる）。`openspec instructions apply --change <name> --json` が返す contextFiles をすべて読み、tasks.md を上から消化して `- [x]` を付け、意味のある粒度で commit する。実装中に設計の欠陥が判明したら artifacts を更新してから続ける。Stack では、各実装 PR の担当 subset を担当 branch 上で消化する。

- main が実装するのが既定。長大な実装は fresh worker に委任する。brief には目的、受け入れ条件、scope、non-goal、参照先（パス / SHA / URL）、許可された変更、禁止された変更、完了条件、検証責任、返却形式を最初からまとめて渡す。Stack では担当 layer（branch 名と tasks subset）を brief に含め、worker は `gh stack` 操作を行わず、下層の修正が必要になったら自分で直さずに main へエスカレーションする
- **発見事項**：実装中に見つけた、受け入れ条件にも設計決定にも紐付かない欠陥や改善点は修正せず、完了報告に列挙だけする（worker が委任先の場合は worker が main へ返す）。main は follow-up 提案として issue にコメントするか PR の残事項に記録する。tasks.md に無い作業を発見を理由に追加しない
- **検証 tier**：初回実装 = full（test / lint / build）、レビュー修正 = compile + 修正対象の targeted tests、承認前の最終 HEAD = full を 1 回。Stack では「初回実装 = full」を実装 PR ごとに適用し、upstack rebase 後は修正した layer の targeted tests + Stack 最上段での full 1 回とする（中間 layer ごとの full を繰り返さない）。最終 full を見込みで先行実行しない。明示された tier 以外に、安心のためだけの再実行、自己 review、追加 reviewer を足さない。追加検証は、失敗、未確認事項、具体的な risk が新たに見つかった場合だけ行う
- **検証記録**：コマンド、結果、実行時 HEAD SHA（Stack では branch 名も）、scope を残す。PR 作成後は PR description の検証セクションを正とし、PR 作成前は worktree 内の一時ノートに残して所在を reviewer への brief に含める。Scenario ごとの証明はテスト名 + SHA で示す。rebase で SHA が変わった layer のうち tier 規則で再検証した layer は再検証後の SHA で記録を更新し、rebase のみで再検証していない layer は「rebase のみ・元の検証 SHA」を記録に明示する（新 SHA へ機械的に書き換えて検証済みに見せない。Stack 最上段の full 1 回が rebase 後の全体を最終的に担保する）
- **production call path**：新しい機能や安全機構には、手組み入力だけで通る unit テストでなく、本番エントリポイントからの配線経由で実際に発動することを確認するテストを要求する。本番経路のテストが書けない場合は理由を明記し、reviewer の重点確認対象とする（純粋な docs 変更等、経路が存在しない場合は「該当なし + 理由」で受理できる）

#### 検証の直列化

heavy validation（Gradle 系、docker build、Testcontainers、使い捨て DB、selftest 類）は同梱の `scripts/validation-lease.sh` で包み、同一マシンで同時 1 本に直列化する。lock 待ち時間は external wait として検証記録に残す。

- JVM 系は worktree ごとに `GRADLE_USER_HOME` を分離する
- 同一 worktree で検証コマンドを並列実行しない。検証は 1 回の呼び出しにまとめる（Gradle は 1 コマンドに複数タスク）
- マシン共有状態に触る復旧操作（共有 daemon の停止、`docker system prune`、プロセス一括 kill）を実装エージェントが独断で行わない。自分の隔離資源内で完結しない復旧は main へエスカレーションする

### 5. PR 作成

push して PR を作る。単一 PR では delta spec も同じ PR に含める。Stack では PR-proposal は反証ゲート通過時に作成済みであり、この段階では実装 PR を Stack 操作の規約に従って上段へ積む（`gh stack submit --auto` → `gh pr edit`）。title は英語、description は日本語で、検証結果と「人間に確認してほしいこと」（agent 仮決めと高リスク・要人間確認の決定の転記先）を含める。OpenSpec artifacts の内容や冗長なコード説明を description に再掲しない。push 前に `git status -sb --untracked-files=all` と `git diff --check` で秘密情報と未追跡ファイルの混入を確認する。CI 待ちは `gh pr checks --watch` 1 回にまとめる（sleep ポーリングの反復は無駄な往復を生むため）。

### 6. レビューループ

reviewer（clean context）に PR、Scenario 一覧、検証記録を渡す。

- **レビュー cadence**：単一 PR では PR 全体に 1 pass。Stack では実装 PR ごとに担当 subset をアンカーにした 1 pass を行い、全実装 PR の収束後に Stack 全体で最終 1 pass を行う（layer 間 interface の齟齬は単一 layer の diff に現れないため。最終 pass のアンカーは change 全体の Scenario ∪ 非退行 invariant）。PR ごとの pass を理由なく反復しない。最終 pass で NEW が出たら通常の修正ラウンドと同様に扱う：main が裁定し、修正を該当 layer の branch へ置いて upstack rebase + tier 規則の再検証を行い、最終 pass を再実行する（実装 PR ごとの pass へは戻らない）。最終 pass の反復も収束判定（must-fix 数の減少）に従う
- **意図アンカー**：各指摘は「delta spec の Requirement/Scenario ∪ 暗黙の非退行 invariant（変更が既存の正しい挙動を壊さない）」のどれを守るための指摘かに紐付く。今回の diff が導入または悪化させた correctness / security / safety / 互換性の regression は非退行 invariant にアンカーできる。既存で未変更の欠陥はアンカー不可で、must-fix でなく follow-up 提案として報告する（報告自体は妨げない）
- **finding の列挙**：今回の diff が導入または悪化させた、根拠を示せる finding は severity で事前に間引かず列挙する。各 finding には再現条件、影響、根拠箇所、意図アンカーを付ける。severity と今回対応すべきかは main が別工程で裁定する
- **信頼チェーン**：reviewer は build / test / lint を再実行せず、検証記録を信頼してコードだけをレビューする。ただし開始前に「検証記録の最終 SHA == 現在の HEAD（Stack ではレビュー対象 branch の HEAD）」を read-only で照合し、不一致または scope 不足ならレビューせず差し戻す。「rebase のみ・元の検証 SHA」と明示された layer は、元の検証 SHA からの差分が rebase による base の移動だけであることを確認できれば受理してよい
- **severity**：must-fix = 受け入れ条件違反、または発生条件を特定できる証明可能な欠陥（データ破壊、race、security、互換性、設計欠陥）。should = 品質や保守性への実害。nit = 好みで、既定処置は「対応不要（記録のみ）」
- **有限 inventory**：must-fix を 1 件見つけたら問題クラスとして一般化し、同根のインスタンスを grep / call graph で列挙して ID を振った inventory として 1 グループで報告する。各 ID に修正を証明する観測（テスト名 / コマンド）を閉じる条件として付け、「全〜」「〜など」の開いた表現を認めない
- **観点の 3 状態**：レビュー観点ごとに checked / unchecked（理由必須）/ isolated_unverified を返させる。変更した gate、例外、戻り値は全呼び出し元を列挙し、受け側が新挙動を安全に処理することまで確認する

main が指摘を裁定する（4 分類：design defect / 今回必須 / follow-up / 過剰）。reviewer のコメントを鵜呑みにせず、今回導入した regression を「新機能のゴールは達成済み」を理由に follow-up へ降格しない。妥当と裁定した指摘だけを PR コメントに投稿する。

修正と再レビューは次のとおり進める。

- 長大な修正は原則として 1 review round につき 1 fresh worker にまとめて委任する。cluster を別 worker へ分割するのは、互いに独立し、各 cluster が単独でも長大な実装になる場合だけとする。小さな修正は main が直接反映し、repo 探索や自己検証だけを目的に worker を spawn しない。worker は根本原因を特定し、同根の経路を列挙してから一括修正する。再検証は main を含む修正実装者が行い、reviewer は代行しない
- Stack で修正が下段 layer に属する場合は、main が該当 branch へ修正を置き、`gh stack rebase --upstack` で上段を追随させてから再検証する（修正を発見した layer に置かない。置き場所を誤ると担当 PR の diff が汚れる）
- 再レビューは inventory ID 単位で CLOSED / PARTIAL（未充足 ID の列挙）/ NEW を判定し、同一指摘の要求を後続ラウンドで拡張しない（inventory 外の経路を後から見つけたら NEW の新規指摘とする）
- 修正コミットが新規に持ち込みやすい欠陥クラス（cache / lock / transaction の境界、置換前後の等価性。消えた LIMIT、bind されない変数）を再レビューで確認する
- 指摘対応に新 layer や新規サブシステムが必要になったら、修正の積み増しでなく default-off 隔離 + 別 change への切り出しを既定とする

### 収束判定

round ごとに未解消 must-fix 数の推移を記録する（Stack では全 PR の合算）。減っていれば続行する（round 数の上限や経過時間では打ち切らない）。横ばい、増加、または同一指摘の PARTIAL 反復が起きたら HANDOFF へ移る。

## 終了条件（G 系ゲート）

G 系ゲートの判定単位は change 全体とする（Stack では全 PR を合わせて 1 つの判定）。

### APPROVED（G1〜G5 がすべて成立）

- **G1 設計**：propose の 4 点セットが `openspec validate` を通過し、反証ゲートの blocking 反例がゼロ
- **G2 証拠**：issue の受け入れ条件を満たす実装が PR（Stack では実装 PR 群）にあり、各 Scenario の証明（テスト名 + SHA + production call path）が受理済みで、検証記録の最終 SHA == 各 branch の HEAD。「rebase のみ・元の検証 SHA」と明示された layer は、元の検証 SHA からの差分が rebase による base の移動だけであることの確認をもって SHA 一致の代替とする
- **G3 収束**：妥当と裁定した must-fix / should がゼロ
- **G4 未確認ゼロ**：safety / migration / security の unchecked がゼロ。unchecked は PR description への転記（可視化）では閉じられず、(1) 人間の回答または観測可能な証拠による checked への再判定 (2) 該当範囲の PR スコープからの分割除外 (3) isolated_unverified 化、のいずれかでのみ閉じる。isolated_unverified は次の 3 条件をすべて reviewer が確認した場合のみ成立し、確認内容を人間確認事項へ転記する。(a) 実効設定が fresh install と既存環境の両方で default-off (b) 別経路（既存設定、環境変数、間接呼び出し）から有効化されない (c) 有効化には別 PR または明示的な検証ゲートが必要
- **G5 同期**：最終 HEAD（Stack では最上段 branch の HEAD）で full validation が成功し、CI の required checks が green で、各 PR の description がその branch の HEAD と同期している

Stack では、G1〜G4 の成立を確認してから PR-archive を最上段へ追加し、その HEAD で最終 full validation を 1 回実行して G5 を判定する（PR-archive 追加前に full を先行実行しない。full は最上段でのこの 1 回だけ）。成立したら最終コメント「APPROVED」を投稿する（単一 PR ではその PR へ、Stack では PR-archive へ。実装 PR には Stack 全体の APPROVED を参照するコメントを残す）。

### HANDOFF（修正を積み増さず整理して終了）

次のいずれかが成立したら HANDOFF へ移る。

1. **収束停滞**：未解消 must-fix 数が round を跨いで減っていない
2. **人間専権**：残った論点が人間の回答や権限なしには閉じられない
3. **新規機構**：対応に新レイヤーや新サブシステムの追加が必要（隔離 + follow-up 提案が既定）

終了前に最終 HEAD で full validation を 1 回試行し、実施可否と結果を残指摘表に記録する（失敗しても HANDOFF は成立する。人間の merge 判断コストを下げるため）。残指摘の表を PR description（Stack では該当 layer の PR）に記録し、最終コメントで「HANDOFF（承認ではない）」と明示する。Stack で PR-archive が未作成なら作らない（G 成立前の archive を積まない）。作成済みの PR-archive がある状態で HANDOFF に入ったら、その PR を close して branch を Stack から外し、archive は merge 後の回収（archive 節）に委ねる。HANDOFF は失敗ではなく、人間レビューへの引き継ぎという正常終了。

### 安全束縛（両状態に優先）

security やデータ破壊級の must-fix を未修正のまま終了できない。default-off / feature flag / stage-out で隔離してから終わるか、隔離不能なら停止して人間判断を求める。

### archive

change の archive は次のいずれかが担う。いずれの場合も merge は人間の専権で、archive の landing が実装より先行しないことを不変条件とする。

- **Stack**：同じ Stack の PR-archive が担う。Stack 最上段の merge により proposal → 実装 → archive の順で landing する
- **単一 PR / fallback / partial merge・merge queue の残り**：run 内では archive しない。partial merge や merge queue の分割 landing で PR-archive が unmerge のまま残った場合も同じ扱いとする。merge 済みで未 archive の change（tasks が全完了、または対応 PR がすべて merged のもののみ。進行中 change の誤 archive を防ぐため）は、次回 run または手動が回収する。回収は feature PR に混ぜず、`openspec archive <name> --yes` の差分だけを載せた独立の回収 PR（`chore:`）として出す。回収 PR はレビューループと G ゲートの対象にしない

HANDOFF 終了時は PR description に follow-up の archive が必須であることを明記する。

### 最終報告

ユーザーに PR URL（Stack では全 PR）、指摘の内訳、検証の最終状態、人間の判断待ち事項を報告する。

## 不変条件

1. **意図アンカー**：すべての生成物（設計決定、指摘、diff）は「どの受け入れ条件、あるいはどの invariant を守るためか」に紐付く。紐付かないものは must-fix にも diff にもなれない
2. **独立反証**：高リスク設計（safety / security / migration / cross-layer 等）は、書いた本人以外の clean context が反証する
3. **収束性による停止**：ループの継続は「must-fix が減っているか」で判定し、round 数の上限や時間では判定しない
4. **証拠ベースの受理**：「対応済み」という自己申告ではなく、観測可能な証拠（テスト名、検証結果、SHA）で受理する
5. **終了状態の二元性**：APPROVED と HANDOFF はどちらも正常終了。「引き継いで終わる」ことは失敗ではない
6. **配送単位の一貫性**：1 issue の intent は 1 change として propose し、分割は PR（配送）の層で行う。archive は実装より先に landing しない

## 運用メモ

- スキル改訂は開始済みの run に反映しない（run 開始時に読んだ版で完走する）
- 対応不能になった worker の作業を main が代行しない。新しい worker に引き継がせる
