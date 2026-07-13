# design

GitHub issue や作業説明を起点に、実装前の設計を確定するためのスキルです。要件の言い換えではなく構造の決定（新規コンポーネントの居場所と責務、ファイル単位の変更マップ、状態遷移・境界の決定）を行い、issue-pr-autopilot にそのまま渡せる設計契約準拠の「## 設計」を作ります。ユーザーの指示があった場合は issue に投稿します。

dig / design / issue-pr-autopilot は 1 つのパイプライン bundle として配布されます（`make link` で一括リンク）。単体配布はサポートしません。

## 使いどころ

- issue を issue-pr-autopilot に渡す前に、設計を確定しておきたいとき
- 「設計して」「実装方針を固めて」「## 設計を書いて」と依頼したいとき
- 複数の実装アプローチから trade-off 付きで選びたいとき

## 設計の要点

- **設計契約の正本化**: 「## 設計」の形式は `references/design-contract.md`（core design schema）が正本。必須 8 セクション（採用アプローチ / 不採用案 / 事実と仮定 / 変更予定ファイル / エッジケースと決定事項 / スコープ判定 / 反証 / レビュー観点）と条件付き matrix 4 種（状態遷移 / consumer / non-functional / deployment）を発動条件付きで定義し、issue-pr-autopilot の設計ゲートとレビューも同じ契約を参照する
- **事実と仮定の分離**: 設計が依拠する値・挙動を config / DB 保存値 / runtime 値 / 表示値の正本ごとに分離し、確認していない値を事実として扱わない。high リスクかつ未検証の仮定は、そのまま設計を確定できない（対話では構造化質問で確定、自走では停止を含む 3 分岐プロトコル）
- **独立反証**: 変更が客観条件リスト（cross-layer / safety / migration / security / 複数 consumer / DB hot path）に該当する場合、設計確定前に clean context の falsifier サブエージェントが `references/falsifier-rubric.md` の反証 5 ベクトルで設計を攻撃する。該当判定は main agent が行い、architect の自己申告に依存しない。該当しない設計は architect が自己反証する。falsifier-rubric の基準で blocking と判定された反例は architect 単独の「受容」で閉じられず、rubric の 4 ルート（設計修正 + falsifier 再確認 / 保証の縮退 / stage-out / ユーザーの明示判断）のいずれかで閉じるまで設計を確定できない（G1）。新機構の追加が必要な対策は stage-out を先に検討し、設計の膨張を避ける。issue スコープ外の既存欠陥を突く反例は blocking ではなく stage-out 提案として返る
- **スコープ判定と stage 予算**: 「1 worker / 1 reviewer で網羅できるか」を客観 signal を根拠に判定し、網羅不能なら staged PR 分割案（各 stage が単独で merge・deploy 可能かつ backward-compatible）を設計成果物にする。各 stage には変更ファイル・diff 行数・binding decision 数の予算目安を適用し、超過見込みは再分割シグナルとする。設計本文は決定だけを書き、400 行超は分割シグナル
- **薄いオーケストレーター + architect サブエージェント**: コード探索と設計立案は最上位ティアの architect サブエージェントに隔離し、main agent は対象特定・反証の発動判定・質問の提示・決定の記録・issue への投稿を行う
- **構造判断と価値判断の分離**: どの層に置くか・どう分割するかは architect が決め、ユーザーの価値判断・リスク許容に関わる論点だけを構造化質問（1 ラウンド 2〜3 問、上限 2 ラウンド）で確定する
- **決定の帰属**: 各決定事項に「ユーザー確認済み」「agent 仮決め」「高リスク・要人間確認」を付け、後二者は issue-pr-autopilot が「人間に確認してほしいこと」へ転記できるようにする
- **成果物の分離**: 分析過程は台帳 `/tmp/design/<slug>.md`、反証入力は設計本文のみのドラフト `<slug>.draft.md`、確定した設計は `<slug>.design.md` に分け、実装エージェントには設計ドキュメントのパスだけを渡す
- **パイプラインの位置**: dig（前提への挑戦）→ design（構造の決定）→ issue-pr-autopilot（実装とレビュー）。dig の Decisions は design が要件・事実・仮定として台帳へ転記する。設計は基本ローカルに確定し、別セッション・別マシンへ渡す場合の共有ストアとして issue の「## 設計」セクションへの投稿をユーザー指示で行う

## ファイル

- `SKILL.md`: スキル本体。全体方針、台帳・ドラフト・設計ドキュメント、architect / falsifier への指示、質問ラウンド、設計確定ゲート（G1）、環境別ヒントを定義します。
- `references/design-contract.md`: core design schema（設計契約の正本）。
- `references/falsifier-rubric.md`: 反証 5 ベクトルと falsifier の職掌・返却形式。
- `references/design-examples.md`: 各セクションの記入例。
- `agents/openai.yaml`: UI メタ情報です。

## リンク

リポジトリ root で以下を実行すると、`~/.claude/skills/design` と `~/.codex/skills/design` に symlink を作成できます。

```bash
make link
```
