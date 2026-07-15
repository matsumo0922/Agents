# issue-pr-autopilot

GitHub issue や短い作業説明を起点に、兄弟 worktree で実装、コミット、PR 作成、reviewer サブエージェントによるレビュー、修正反復までを自走させるためのスキルです。

dig / design / issue-pr-autopilot / claude-rescue は 1 つのパイプライン bundle として配布されます（`make link` で一括リンク）。単体配布はサポートしません。設計の形式は design スキルの `references/design-contract.md`（設計契約）が正本で、本スキルは構造検査に必要な最小限を gate schema として持ちます。claude-rescue は Claude サブエージェントを持たない環境（Codex 等）で reviewer / falsifier を呼び出すブリッジです。

## 使いどころ

- issue URL や issue 番号を渡して、そのまま PR 作成まで進めたいとき
- main agent に進行管理と判断だけをさせ、実装・検証・レビューをサブエージェントに分けたいとき
- PR 上に round 1 のレビューとレビューサマリー付き最終コメントを残しながら、予算内で修正と再レビューを回したいとき

## 設計の要点

品質保証の最終責任は人間の PR レビューが担い、本スキルは「証拠と未確認事項が整理され、人間が短時間で判断できる PR」を最短で出すことを責務とします。実行速度・トークン効率・収束性のため、次の規律を中心に設計しています。

- **main agent は判断専任**: 実装・検証コマンド実行・ソースのフル読みをせず、worker / reviewer の構造化レポートで判断する。ゲート判定はすべて構造検査。サブエージェントが停止しても代行せず、新しいサブエージェントに引き継がせる
- **意図アンカー**: すべての生成物（設計決定・レビュー指摘・修正 diff）に「issue の受け入れ条件・設計 invariant のどれを守るためか」の紐付けを必須にする。紐付けられない指摘は must-fix にできず follow-up 提案に分類され、紐付けられない変更は diff に含めない
- **終了状態は APPROVED / HANDOFF の 2 つ**: APPROVED = G5 の全条件を満たした状態（safety/migration/security の unchecked なし〔人間回答・分割除外・条件付き isolated_unverified で解消〕+ 仮承認後の最終 HEAD full validation 1 回 + PR description 同期 + required checks 成功）。HANDOFF = 収束停滞・人間専権・G5 未達での内部処理終了で、承認ではない。残指摘・cycle 表を PR に記録して人間に引き渡す
- **受理ゲート G2〜G4**: G2 = 設計の gate schema 適合（必須セクション・条件付き matrix の発動・非該当宣言）、G3 = worker evidence matrix の受理（全行の具体性・production call path・SHA 一致。「全件修正済み」の要約だけの報告は不受理）、G4 = レビュー開始前の検証台帳 SHA と validation scope の照合
- **収束判定と HANDOFF**: 数値の停止閾値（round 上限・PARTIAL 回数・diff 倍率・時間 SLO）を置かず、round ごとに「未解消 must-fix 数が減少しているか」「新規指摘が意図アンカーを満たすか」で継続を判定する。収束している限り round 数で打ち切らず、収束停滞（減少停止・PARTIAL 反復・inventory 外拡張の継続）または人間専権事項のみで HANDOFF する（security・データ破壊級の must-fix は default-off / feature flag / stage-out で隔離してから終了）。designer / worker の規模申告は裁定・報告の材料で、自動停止には使わない
- **設計ゲートと反証**: 設計が無い複数レイヤー変更は designer が設計契約準拠で設計し、客観条件リスト（cross-layer / safety / migration / security / 複数 consumer / DB hot path）に該当すれば clean context の falsifier が設計を反証してから実装に入る。該当判定は main が行う。falsifier-rubric の基準で blocking と判定された反例は designer 単独の「受容」で閉じられず、rubric の 4 ルート（設計修正 + falsifier 再確認 / 保証の縮退 / stage-out / 人間判断）のいずれかで閉じるまで worker を spawn しない（新機構の追加が必要な対策は stage-out を先に検討する）。高リスクな未検証前提は 3 分岐プロトコル（安全性・不可逆性を左右する未確定は停止 / reversible な stage のみ進行 / 既存状態維持のみ fail-safe 仮決め）で扱う
- **スコープ分割 gate**: 設計のスコープ判定が「1 worker / 1 reviewer で網羅不能」なら、自走時は第 1 stage のみ実装して `Refs #<issue>` の PR とし、残 stage は issue に分割提案コメントを投稿する。元の受け入れ条件は stage mapping で保持する
- **worker evidence matrix**: 完了報告は「条件 / 実装箇所 / production call path / 証明テスト名 / 検証結果 + SHA」の evidence matrix（受け入れ条件・invariant・裁定済み must-fix と 1:1 対応）と規模の申告が必須。レビュー修正は finding cluster 単位で、cluster ごとに fresh の修正 worker が狭い入力で行う（compaction を跨いだ worker に修正を継続させない）
- **検証 tier と信頼チェーン**: 検証結果は「コマンド / 結果 / HEAD SHA / validation scope」の台帳で共有し、reviewer はテストを再実行しない。初回 = full、レビュー修正 = compile + targeted、rebase = affected、仮承認後の最終 HEAD = full 1 回（G5 必須）。heavy validation は同梱の `scripts/validation-lease.sh`（OS advisory lock。クラッシュ時解放を kernel が保証）でマシン全体 1 本に直列化し、worktree ごとに `GRADLE_USER_HOME` を分離する。証明は Tier A（決定的テスト）〜 Tier D（deploy 後観測）から十分な最も低い tier を選び、環境依存で決定的にできない挙動は targeted テスト 1 本 + 後段 tier の宣言（safety / security は default-off 隔離付き）で証明できる
- **reviewer round 1 は 2 パス**: pass 1 が設計反証（反証 5 ベクトル・非該当宣言の検証・高リスクマークの前提）、pass 2 が実装レビュー（call graph 追跡・evidence 突合・修正コミット固有欠陥クラス）。手順は `references/review-rubric.md`。設計欠陥は worker でなく designer に差し戻す。結果は review point 単位の checked / unchecked / isolated_unverified（default-off 隔離を 3 条件で確認した状態。checked とは区別する）の matrix で返し、unchecked と isolated_unverified は PR の「人間に確認してほしいこと」へ転記する
- **round 1 で出し尽くす + 有限 closure**: must-fix は意図アンカーと、同根クラスの全経路をまとめた ID 付き有限 inventory・「閉じる条件」を付けて初めて成立する。nit の既定処置は「対応不要（記録のみ）」。再レビューは inventory ID 単位の CLOSED / PARTIAL / NEW 判定のみで、同一指摘の要求を拡張しない。main は must-fix を 4 分類に裁定する。まず設計欠陥ラベルを最優先で design defect に振り、残りを意図アンカー（受け入れ条件・明示 invariant・今回導入した regression の暗黙の非退行 invariant）で今回必須 / follow-up / 過剰 に分類する。アンカー済みの regression は「新機能のゴールは達成済み」を理由に follow-up へ降格できず、follow-up はアンカー不能な既存欠陥・スコープ外改善に限る
- **cycle / round の分離と計測**: 外部レビューは常に、CI failure・rebase は material な場合のみ新 cycle とし、round は cycle 内で数え直す（routine な再レビューを新 cycle に誤分類しない）。round ごとに finding origin・regression 件数・未解消 must-fix 数の推移・意図アンカー違反件数・役割別モデルと G3 差し戻し・HANDOFF 判定根拠・時間 4 区分（wall-clock / cumulative compute / critical-path / external wait）を即時記録し、最終コメントへ cycle 表として転記する
- **GitHub 投稿の最小化と妥当性判断の先行**: reviewer は GitHub に投稿せず review_result を main に返し、main が全指摘の妥当性を判断してから、妥当な指摘だけを round 1 レビューコメントとして投稿する。PR に投稿するのは round 1 レビューと最終コメント（サマリー + 指摘対応表 + cycle 表）のみ。PR description の更新も main の責務
- **役割別モデル割当**: 「細部への目配りは設計では資産、レビューでは負債」を原則に、designer / 実装 worker = 細部まで目の届くモデルの high、falsifier / reviewer = 別ベンダーの判断特化モデル（triage 較正重視）、修正 worker = 軽量高速モデルの pilot。effort は全役割 high 既定で、足りなければ effort でなくモデルを上げる。具体的な割当表・Fable 5 の発動条件・claude-rescue ブリッジの利用規則は SKILL.md の「環境別ヒント」に定義
- **進捗はメッセージではなく worktree 観察**: 実行中の worker への進捗確認メッセージはターンを乱すため送らず、worker worktree の git log / status / diff を読み取り専用で観察する。停滞判定は経過時間ではなく worktree の無変化で行う

## ファイル

- `SKILL.md`: スキル本体。goal 設定、gate schema、コンテキストノート、設計ゲートと反証パス、worktree 作成、検証 tier、worker / reviewer への指示、受理ゲート、PR description の形式、レビュー反復、cycle 定義と計測、環境別ヒントを定義します。
- `references/review-rubric.md`: reviewer round 1 の 2 パス手順、review point matrix の形式、evidence matrix 突合基準。
- `scripts/validation-lease.sh`: heavy validation をマシン全体で 1 本に直列化する lease helper（OS advisory lock）。
- `agents/openai.yaml`: UI メタ情報です。

## リンク

リポジトリ root で以下を実行すると、`~/.claude/skills/issue-pr-autopilot` と `~/.codex/skills/issue-pr-autopilot` に symlink を作成できます。

```bash
make link
```
