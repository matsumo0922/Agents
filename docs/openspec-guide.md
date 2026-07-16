# OpenSpec 開発ガイド

[OpenSpec](https://github.com/Fission-AI/OpenSpec) を使って開発を進めるためのガイド。
読者として OpenSpec 未経験の開発者を想定し、本リポジトリのスキルとは独立に、OpenSpec 単体の使い方を説明する。
記述は OpenSpec 1.6 系の実挙動に基づく。

## OpenSpec が解く問題

OpenSpec は**仕様駆動開発**（spec-driven development）のためのツールである。
コードを書く前に「何を作るか」を仕様として確定し、実装後はその仕様をプロジェクトの正式な記録として維持する。

中心にあるのは、リポジトリ直下の `openspec/` ディレクトリにおける二つの領域の分離である。

- **specs/**：現在の仕様。プロジェクトが今どう振る舞うかを、機能（capability）ごとに現在形で記述する
- **changes/**：進行中の提案。これから加える変更を、提案ごとのフォルダとして保持する

変更は changes/ の提案として生まれ、実装と merge を経て specs/ へ取り込まれる。
「今の姿」と「これからの変更」が構造的に分かれているため、仕様書が過去と未来の記述で濁らない。

## 導入

公式チャネルは npm である（Homebrew の formula は upstream 非公式のため使わない）。

```bash
npm install -g @fission-ai/openspec@latest
openspec init --tools claude,codex
```

`openspec init` は `openspec/config.yaml` と、AI エージェント向けのスラッシュコマンドおよびスキル（`--tools` で指定した環境の設定ディレクトリ、たとえば `.claude/` と `.codex/`）を生成する。
`specs/` と `changes/` は必要になった時点で作られる。

## CLI とスラッシュコマンドの関係

OpenSpec には二つの入口がある。

- **CLI**（`openspec` コマンド）：セットアップと状態管理を担う。change の作成、進捗の照会、検証、archive を機械的に実行する
- **スラッシュコマンド**（`/opsx:*`）：エージェントに読み込まれるプロンプトで、skill に相当する。エージェントはこのプロンプトに従い、内部で CLI を呼びながら成果物を書く

つまり、人間が状態を確認したいときは CLI を直接叩き、エージェントに作業させたいときはスラッシュコマンドを使う。

## 主要スラッシュコマンド

| コマンド | 役割 |
|---|---|
| `/opsx:explore` | 提案前の思考パートナー。実装せずに、問題の調査とアイデアの明確化に付き合う |
| `/opsx:propose` | 4 点セット（proposal.md / delta spec / design.md / tasks.md）を生成し、実装可能な提案に仕上げる |
| `/opsx:apply` | tasks.md に沿って実装し、完了したタスクにチェックを入れる |
| `/opsx:archive` | 提案を畳む。delta を specs/ へマージし、change フォルダを `changes/archive/` へ移す |
| `/opsx:update` | 作成済みの成果物を、要件の変化に合わせて更新する |
| `/opsx:sync` | archive せずに、delta の内容を specs/ へ反映する |

4 点セットの各ファイルは次の問いに答える。

- **proposal.md**：なぜこの変更をするのか
- **delta spec**（`specs/<capability>/spec.md`）：仕様に何を足し、何を変え、何を消すのか
- **design.md**：どう作るのか
- **tasks.md**：どの順で実装するのか（チェックリスト）

## delta spec の書式

delta spec は、既存仕様との差分を `## ADDED Requirements` / `## MODIFIED Requirements` / `## REMOVED Requirements` の見出しで宣言する。
各 Requirement は SHALL 文で要求を述べ、少なくとも一つの Scenario（GIVEN / WHEN / THEN）で検証可能な振る舞いを示す。

```markdown
## ADDED Requirements

### Requirement: Greeting
The system SHALL print "hello" when invoked.

#### Scenario: Default greeting
- GIVEN the CLI is installed
- WHEN the user runs `hello`
- THEN "hello" is printed
```

archive すると、この差分が CLI によって機械的に `openspec/specs/<capability>/spec.md` へマージされ、現在形の仕様になる。

## 開発 1 周の流れ

```text
/opsx:explore（問題を調査し、要件を明確にする）
    ↓
/opsx:propose（4 点セットを生成する）
    ↓
人間レビュー（proposal と design を読み、方向を承認する）
    ↓
/opsx:apply（tasks.md を上から実装し、チェックを入れる）
    ↓
PR と merge（通常の Git フロー。delta spec も同じ PR に含める）
    ↓
/opsx:archive（delta を specs/ にマージし、提案を畳む）
```

explore と propose の間、apply の途中でも、成果物は `/opsx:update` でいつでも直せる。
フェーズに縛られず、実装中に設計の穴が見つかったら成果物へ戻ってよい。

## config.yaml によるカスタマイズ

`openspec/config.yaml` はユーザー所有のカスタマイズ層で、二つの注入点を持つ。

- **context**：プロジェクトの背景（技術スタック、規約、ドメイン知識）。成果物を作るすべての場面でエージェントに渡される
- **rules**：成果物の種類ごとの追加規則（例として「proposal は 500 語以内」「tasks は 2 時間以内の粒度に分割」）

生成されたスラッシュコマンドやスキルのファイルを直接編集してはならない。
`openspec update --force` や版の upgrade で上書きされて消えるからである。
恒久的なカスタマイズは config.yaml に置くか、上書きの影響を受けない自前の skill として管理する。

## 状態管理に使う CLI

| コマンド | 用途 |
|---|---|
| `openspec list --json` | アクティブな change の一覧 |
| `openspec status --change <name> --json` | 成果物の完成状態と依存関係 |
| `openspec instructions <artifact> --change <name> --json` | 成果物を書くための指示、テンプレート、出力先 |
| `openspec instructions apply --change <name> --json` | 実装に読むべきファイル一覧とタスク進捗 |
| `openspec validate <name>` | change の構造検証 |
| `openspec archive <name> --yes` | 非対話での archive |

`--json` 付きの出力は、エージェントや自動化スクリプトからの利用を想定した機械可読形式である。
誤って archive した場合は、`changes/archive/` 配下のフォルダを `changes/` へ戻すだけで CLI が再認識する。
