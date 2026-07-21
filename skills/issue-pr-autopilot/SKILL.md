---
name: issue-pr-autopilot
description: "GitHub issue や作業説明を起点に、OpenSpec の propose→apply を専用 worktree 内で駆動し、反証ゲート・レビューループ・収束判定を経て、人間が短時間で merge 判断できる PR を自走で作る配送シェル。Use when the user wants to turn an issue or task description into a reviewed pull request with autonomous subagents and worktrees, issue を PR にして, autopilot で実装して, 自走で PR まで進めて."
---

# Issue PR Autopilot

## 目的

issue または作業説明から、「証拠と未確認事項が整理され、人間が短時間で merge 判断できる PR」を最短で出す。品質保証の最終責任は人間の PR レビューにあり、内部ループで完璧を目指さない。速度は品質と同格の要件であり、最少の有用なループで終了条件を満たしたらそれ以上磨かない。ただしループ削減を、正確性と必須の証拠より優先しない。

OpenSpec との役割分担として、成果物の形式（proposal.md / delta spec / design.md / tasks.md）、進捗の外部記録、仕様の永続化（`openspec/specs/`）は OpenSpec が担う。本スキルはその propose→apply を駆動する配送シェルとして、worktree 管理、反証ゲート、PR 作成、レビューループ、収束判定、終了状態（APPROVED / HANDOFF）を担う。

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

## エージェント構成

main が文脈を全部持つリード役として、propose、実装、裁定、収束判定を自分で行う。clean context の隔離は敵対的役割だけに適用する。

- **falsifier / reviewer**：clean context。書き手と実装者の弁明を渡さない
- **worker**：「長大な実装」と「レビュー修正ラウンド（裁定者と修正者の分離）」でのみ fresh spawn し、main が書いた濃い brief を渡す
- **architect**：propose は main が自分で行うのが既定。設計作業を委任する場合のみ spawn する

サブエージェント間の受け渡しは要約と参照（パス、SHA、URL）で行い、ネストさせない（中継のたびに文脈が劣化コピーになるため）。spawn のたびに割り当てモデル名を進捗報告に明示する。

### モデル割当

main は常にセッションのモデル。subagent は実行環境ごとに次表を既定とする。

| 役割 | Claude Code（Claude のみ） | Codex（GPT のみ） | Claude Code（クロスモデル） |
|---|---|---|---|
| architect（委任時） | Opus 4.8 / high | gpt-5.6-sol / medium | Opus 4.8 / high |
| falsifier | Opus 4.8 / high | gpt-5.6-sol / high | gpt-5.6-sol / high |
| worker | Sonnet 5 / high | gpt-5.6-sol / medium | gpt-5.6-sol / medium |
| reviewer | Opus 4.8 / high | gpt-5.6-sol / high | Opus 4.8 / high |

- **呼び出し方**：Claude モデルは Task の `model` 指定（`opus` / `sonnet` / `fable`）で呼び、effort はセッション既定を継承する。GPT モデルは `~/.claude/agents/` の agent 定義（`gpt-medium` / `gpt-high` / `gpt-xhigh`）で呼び、effort は定義の frontmatter が決める
- **昇格**：反証ゲートの高リスク基準（safety / security / migration / cross-layer / 複数 consumer / DB hot path）に触れる対象への falsifier / reviewer は、main が spawn 前に 1 段上へ昇格する。Opus 4.8 → Fable 5（effort はセッション既定）、gpt-5.6-sol high → xhigh
- **fallback**：GPT の agent 定義が無い環境（プロキシを経由しない直結環境など）では、クロスモデル列を使わず「Claude のみ」列で全役割を賄う。Claude subagent が無い環境では「Codex」列で賄う

## 進め方

### 1. worktree と propose

- 兄弟ディレクトリに worktree + branch を作る。propose より先に行い、main checkout を汚さない。検証に必要な未追跡ファイル（`local.properties` / `.env` 等）だけをコピーし、.gitignore に守られていることを確認する
- worktree 内で、merge 済みで未 archive の change を `openspec archive <name> --yes` で回収する。回収対象は「tasks が全完了、または対応 PR が merged の change」のみ（進行中 change の誤 archive を防ぐため）。archive 差分はこの run の最初の commit に含め、PR で人間が確認できるようにする
- `openspec/changes/<name>/` が既にあればそれを使う。無ければ worktree 内で propose する。`openspec new change` で作成し、`openspec status --change <name> --json` と `openspec instructions <artifact> --change <name> --json` に従って 4 点セット（proposal.md / delta spec / design.md / tasks.md）を書き、`openspec validate <name>` を通してから最初の commit を打つ
- 提案は受け入れ条件を満たす最小のものを既定とする。受け入れ条件が複数の解釈を許す場合は最小の解釈を採り、より広い解釈は提案に含めず質問または follow-up として残す。提案の拡張は、反証・レビュー・検証のいずれかが実際に失敗を示した場合にのみ行い、「あった方が良い」「将来必要になる」を理由に先回りしない
- 設計上の各決定には帰属タグ（ユーザー確認済み / agent 仮決め / 高リスク・要人間確認）を付ける。高リスク未検証前提の 3 分岐プロトコルと質問の作法は falsify スキルの規約に従う
- stage 分割を行う場合（falsify のスコープ判定が blocking として検出し、処置の stage-out / 人間判断から入る）は、stage ごとに独立の change + PR とする。受け入れ条件との対応（この stage / 後続 stage / non-goal）を proposal.md に記録し、残 stage は issue にコメントで残す

### 2. 反証ゲート

safety / security / migration / cross-layer / 複数 consumer / DB hot path に触れる提案は、falsify スキルの独立 falsifier に proposal + delta spec を反証させる。blocking 反例が解消される（falsify の処置 4 ルートのいずれかで閉じる）まで実装に入らない。

### 3. 実装（apply）

apply の意味論は本スキルが定義する（OpenSpec のスラッシュコマンド実体に依存せず、CLI と change 名だけで完結させる）。`openspec instructions apply --change <name> --json` が返す contextFiles をすべて読み、tasks.md を上から消化して `- [x]` を付け、意味のある粒度で commit する。実装中に設計の欠陥が判明したら artifacts を更新してから続ける。

- main が実装するのが既定。長大な実装は fresh worker に委任し、brief には issue の文脈、tasks.md の場所、検証の期待を含める
- **発見事項**：実装中に見つけた、受け入れ条件にも設計決定にも紐付かない欠陥や改善点は修正せず、完了報告に列挙だけする（worker が委任先の場合は worker が main へ返す）。main は follow-up 提案として issue にコメントするか PR の残事項に記録する。tasks.md に無い作業を発見を理由に追加しない
- **検証 tier**：初回実装 = full（test / lint / build）、レビュー修正 = compile + 修正対象の targeted tests、承認前の最終 HEAD = full を 1 回。最終 full を見込みで先行実行しない
- **検証記録**：コマンド、結果、実行時 HEAD SHA、scope を残す。PR 作成後は PR description の検証セクションを正とし、PR 作成前は worktree 内の一時ノートに残して所在を reviewer への brief に含める。Scenario ごとの証明はテスト名 + SHA で示す
- **production call path**：新しい機能や安全機構には、手組み入力だけで通る unit テストでなく、本番エントリポイントからの配線経由で実際に発動することを確認するテストを要求する。本番経路のテストが書けない場合は理由を明記し、reviewer の重点確認対象とする（純粋な docs 変更等、経路が存在しない場合は「該当なし + 理由」で受理できる）

#### 検証の直列化

heavy validation（Gradle 系、docker build、Testcontainers、使い捨て DB、selftest 類）は同梱の `scripts/validation-lease.sh` で包み、同一マシンで同時 1 本に直列化する。lock 待ち時間は external wait として検証記録に残す。

- JVM 系は worktree ごとに `GRADLE_USER_HOME` を分離する
- 同一 worktree で検証コマンドを並列実行しない。検証は 1 回の呼び出しにまとめる（Gradle は 1 コマンドに複数タスク）
- マシン共有状態に触る復旧操作（共有 daemon の停止、`docker system prune`、プロセス一括 kill）を実装エージェントが独断で行わない。自分の隔離資源内で完結しない復旧は main へエスカレーションする

### 4. PR 作成

push して PR を作る（delta spec も同じ PR に含める）。title は英語、description は日本語で、検証結果と「人間に確認してほしいこと」（agent 仮決めと高リスク・要人間確認の決定の転記先）を含める。冗長なコード説明は載せない。push 前に `git status -sb --untracked-files=all` と `git diff --check` で秘密情報と未追跡ファイルの混入を確認する。CI 待ちは `gh pr checks --watch` 1 回にまとめる（sleep ポーリングの反復は無駄な往復を生むため）。

### 5. レビューループ

reviewer（clean context）に PR、Scenario 一覧、検証記録を渡す。

- **意図アンカー**：各指摘は「delta spec の Requirement/Scenario ∪ 暗黙の非退行 invariant（変更が既存の正しい挙動を壊さない）」のどれを守るための指摘かに紐付く。今回の diff が導入または悪化させた correctness / security / safety / 互換性の regression は非退行 invariant にアンカーできる。既存で未変更の欠陥はアンカー不可で、must-fix でなく follow-up 提案として報告する（報告自体は妨げない）
- **信頼チェーン**：reviewer は build / test / lint を再実行せず、検証記録を信頼してコードだけをレビューする。ただし開始前に「検証記録の最終 SHA == 現在の HEAD」を read-only で照合し、不一致または scope 不足ならレビューせず差し戻す
- **severity**：must-fix = 受け入れ条件違反、または発生条件を特定できる証明可能な欠陥（データ破壊、race、security、互換性、設計欠陥）。should = 品質や保守性への実害。nit = 好みで、既定処置は「対応不要（記録のみ）」
- **有限 inventory**：must-fix を 1 件見つけたら問題クラスとして一般化し、同根のインスタンスを grep / call graph で列挙して ID を振った inventory として 1 グループで報告する。各 ID に修正を証明する観測（テスト名 / コマンド）を閉じる条件として付け、「全〜」「〜など」の開いた表現を認めない
- **観点の 3 状態**：レビュー観点ごとに checked / unchecked（理由必須）/ isolated_unverified を返させる。変更した gate、例外、戻り値は全呼び出し元を列挙し、受け側が新挙動を安全に処理することまで確認する

main が指摘を裁定する（4 分類：design defect / 今回必須 / follow-up / 過剰）。reviewer のコメントを鵜呑みにせず、今回導入した regression を「新機能のゴールは達成済み」を理由に follow-up へ降格しない。妥当と裁定した指摘だけを PR コメントに投稿する。

修正と再レビューは次のとおり進める。

- 修正は finding cluster ごとに fresh worker に委任する（根本原因を特定し、同根の経路を列挙してから一括修正）。再検証は修正した実装者が行い、main や reviewer は代行しない
- 再レビューは inventory ID 単位で CLOSED / PARTIAL（未充足 ID の列挙）/ NEW を判定し、同一指摘の要求を後続ラウンドで拡張しない（inventory 外の経路を後から見つけたら NEW の新規指摘とする）
- 修正コミットが新規に持ち込みやすい欠陥クラス（cache / lock / transaction の境界、置換前後の等価性。消えた LIMIT、bind されない変数）を再レビューで確認する
- 指摘対応に新 layer や新規サブシステムが必要になったら、修正の積み増しでなく default-off 隔離 + 別 change への切り出しを既定とする

### 収束判定

round ごとに未解消 must-fix 数の推移を記録する。減っていれば続行する（round 数の上限や経過時間では打ち切らない）。横ばい、増加、または同一指摘の PARTIAL 反復が起きたら HANDOFF へ移る。

## 終了条件（G 系ゲート）

### APPROVED（G1〜G5 がすべて成立）

- **G1 設計**：propose の 4 点セットが `openspec validate` を通過し、反証ゲートの blocking 反例がゼロ
- **G2 証拠**：issue の受け入れ条件（stage 分割時は当該 stage の subset）を満たす実装が PR にあり、各 Scenario の証明（テスト名 + SHA + production call path）が受理済みで、検証記録の最終 SHA == HEAD
- **G3 収束**：妥当と裁定した must-fix / should がゼロ
- **G4 未確認ゼロ**：safety / migration / security の unchecked がゼロ。unchecked は PR description への転記（可視化）では閉じられず、(1) 人間の回答または観測可能な証拠による checked への再判定 (2) 該当範囲の PR スコープからの分割除外 (3) isolated_unverified 化、のいずれかでのみ閉じる。isolated_unverified は次の 3 条件をすべて reviewer が確認した場合のみ成立し、確認内容を人間確認事項へ転記する。(a) 実効設定が fresh install と既存環境の両方で default-off (b) 別経路（既存設定、環境変数、間接呼び出し）から有効化されない (c) 有効化には別 PR または明示的な検証ゲートが必要
- **G5 同期**：最終 HEAD で full validation が成功し、CI の required checks が green で、PR description が最終 HEAD と同期している

成立したら最終コメント「APPROVED」を投稿する。

### HANDOFF（修正を積み増さず整理して終了）

次のいずれかが成立したら HANDOFF へ移る。

1. **収束停滞**：未解消 must-fix 数が round を跨いで減っていない
2. **人間専権**：残った論点が人間の回答や権限なしには閉じられない
3. **新規機構**：対応に新レイヤーや新サブシステムの追加が必要（隔離 + follow-up 提案が既定）

終了前に最終 HEAD で full validation を 1 回試行し、実施可否と結果を残指摘表に記録する（失敗しても HANDOFF は成立する。人間の merge 判断コストを下げるため）。残指摘の表を PR description に記録し、最終コメントで「HANDOFF（承認ではない）」と明示する。HANDOFF は失敗ではなく、人間レビューへの引き継ぎという正常終了。

### 安全束縛（両状態に優先）

security やデータ破壊級の must-fix を未修正のまま終了できない。default-off / feature flag / stage-out で隔離してから終わるか、隔離不能なら停止して人間判断を求める。

### archive

この run の change は run 内で archive しない（merge は人間の専権で、archive は merge 後）。merge 済み change は次回 run が worktree 内で回収するか、手動の `openspec archive` が回収し、delta を `specs/` へマージして現在形の仕様にする。HANDOFF 終了時は PR description に follow-up の archive が必須であることを明記する。

### 最終報告

ユーザーに PR URL、指摘の内訳、検証の最終状態、人間の判断待ち事項を報告する。

## 不変条件

1. **意図アンカー**：すべての生成物（設計決定、指摘、diff）は「どの受け入れ条件、あるいはどの invariant を守るためか」に紐付く。紐付かないものは must-fix にも diff にもなれない
2. **独立反証**：高リスク設計（safety / security / migration / cross-layer 等）は、書いた本人以外の clean context が反証する
3. **収束性による停止**：ループの継続は「must-fix が減っているか」で判定し、round 数の上限や時間では判定しない
4. **証拠ベースの受理**：「対応済み」という自己申告ではなく、観測可能な証拠（テスト名、検証結果、SHA）で受理する
5. **終了状態の二元性**：APPROVED と HANDOFF はどちらも正常終了。「引き継いで終わる」ことは失敗ではない

## 運用メモ

- スキル改訂は開始済みの run に反映しない（run 開始時に読んだ版で完走する）
- 対応不能になった worker の作業を main が代行しない。新しい worker に引き継がせる
