# パイプライン forward test

dig → design → issue-pr-autopilot パイプライン（設計契約・ゲート・反証・evidence gate・cycle 管理）が、issue #21 で確認された故障クラスを再現する入力に対して期待どおり振る舞うことを検証する forward test の定義と、実行結果の証拠を記録するドキュメント。

## 実行方法（汚染防止ハーネス）

- **test agent**（スキルを実行するエージェント）に渡すのは、raw issue fixture・raw repository fixture・対象スキル（dig / design / issue-pr-autopilot / claude-rescue の 4 スキル bundle）だけとする。本ドキュメント・期待結果・評価 rubric・既知の故障の情報を渡さず、「スキルを検証している」と伝えない。
- fixture リポジトリは Agents リポジトリ外の使い捨てディレクトリに作る。対象スキルも一時ディレクトリへ export し、Agents リポジトリ本体（docs・issue 由来の artifact を含む）へ到達できない状態で実行する。
- 各 run は fresh thread + fresh worktree で実行し、前 run の生成物を次 run から見えなくする。
- **evaluator**（期待結果と照合するエージェントまたは人間）は、test agent の生成物（設計・レビュー結果・ゲート判定）が完成した後に本ドキュメントのチェックリストと照合し、証拠セクションへ記録する。記録は実行後に行い、実行前に test agent の worktree へ期待答えを置かない。

## シナリオ族 1: 状態移行・評価 scope 型

### fixture の入力条件

架空の取引システムリポジトリと issue を用意する。次の特徴を含める。

- config 上の初期資金と、DB 保存値（テスト fixture で表現）と、runtime が実際に使う値が異なる。
- 不整合中に open risk（未決済ポジション相当）が存在する。
- risk-increasing 操作（entry）と risk-reducing 操作（決済・手動 close）が同じ write 経路を通る。
- 評価値の consumer が複数（API / UI / バッチ）あり、期間・truncation・cohort の扱いが異なる。
- schema 追加と least-privilege role provisioning を伴う。
- issue は「基準資金を epoch として固定し評価を分離する」類の複数レイヤー変更を要求する。

### 期待結果（観測可能なチェック）

| # | チェック | 観測方法 |
|---|---|---|
| 1-1 | 生成された設計の「事実と仮定」が config / DB 保存値 / runtime 値 / 表示値の正本を分離している | 設計の事実表に所在列があり、不一致が事実として記録されている |
| 1-2 | 安全状態へ戻す操作（決済・close）を塞ぐ設計が、falsifier または reviewer pass 1 で must-fix（設計欠陥）になる | 反証セクションまたは review_result に safety direction の反例がある |
| 1-3 | consumer matrix が生成される（または非該当宣言が正当な理由付きで存在する） | 設計のセクション有無 |
| 1-4 | deployment 手順に migration と role provisioning の順序制約が書かれる | 設計のセクション有無と順序の記載 |
| 1-5 | スコープ判定が客観 signal を根拠に staged PR 分割を提案する | スコープ判定セクションと stage mapping の有無 |
| 1-6 | main の falsifier 発動判定が「該当」（cross-layer + safety + migration）になり、独立 falsifier が spawn される | 実行ログ上の spawn とその入力（設計ドラフト + rubric のみ） |

## シナリオ族 2: request 監査・複合 failure 型

### fixture の入力条件

架空の外部 API クライアントを持つリポジトリと issue を用意する。次の特徴を含める。

- request boundary で監査 event を同期 DB 保存する要求。
- audit failure と network failure が同時に発生し得る。
- background の保護処理（reconciler 相当）が degraded input（例外・null）を受け取る。
- production の呼び出し元が複数 process / entrypoint に分かれている。
- rebase で認証・manifest 方式が変わる状況（base 差分との material overlap）を含める。

### 期待結果（観測可能なチェック）

| # | チェック | 観測方法 |
|---|---|---|
| 2-1 | fail-closed 化した例外の受け側（保護処理）が最終状態まで call graph で追跡され、握りつぶしが指摘される | 反証セクションまたは reviewer pass 2 の call graph 追跡結果 |
| 2-2 | 複合 failure（audit + network）の優先順位と安全な diagnostics が設計に決められる | 状態遷移 matrix またはエッジケースの決定事項 |
| 2-3 | non-functional contract に event 量・同期 DB latency の budget が「既知 / 推定 / 未測定」の分類付きで書かれ、未測定に測定方法と fail-safe 上限がある | 設計のセクション内容 |
| 2-4 | production constructor / factory で audit sink が必須化される（Noop default の silent 配線漏れが指摘される） | 設計または review_result |
| 2-5 | rebase（material overlap あり）が新しい review cycle として扱われ、round がリセットされる | 計測ログの cycle 表 |
| 2-6 | worker の完了報告が evidence matrix 形式で、production call path 列が「テストからのみ到達」でない | G3 受理時の evidence matrix |

## シナリオ族 3: 収束・負荷型

シナリオ族 1・2 は must-fix が少ない軽負荷経路しか通らないため、レビューループの収束性は本族で検証する（背景: issue #23）。skill のレビュー・ゲート・予算まわりを改訂する PR は、本族の実行を合格条件に含める。owner の明示判断がある場合に限り、検証を実運用計測（cycle 表による回復確認）へ代替できるが、その場合の改訂は**計測記録が「実行結果の証拠」へ追記されるまで未検証の実験的導入として扱う**（代替の決定だけでは合格条件を満たさない）。代替の決定・根拠は該当 PR に、計測記録は本ドキュメントに記録する。

### fixture の入力条件

シナリオ族 1 または 2 の fixture に、次を満たす欠陥を意図的に混入した実装を与え、レビューループから開始する。

- round 1 のレビューが must-fix 5 件以上を返す密度の欠陥（同根クラスを含む）。
- 修正すると新しい欠陥を持ち込みやすい箇所（共有ヘルパー・置換系）を 1 つ以上含める。
- 既存 API の挙動を実際に壊す共有ヘルパー変更を初期実装に必ず含める。壊れる既存挙動は issue の受け入れ条件に書かず、暗黙の非退行 invariant にだけアンカーできる状態にする（3-9 の検証対象。この regression が実在しない run は 3-9 を合格にしない）。
- 設計レベルの欠陥（修正に新規機構の追加を要するもの）を 1 件含める。
- 環境依存で決定的にテストできない挙動（プロセス終端・並行実行相当）への指摘を誘発する箇所を 1 つ含める。

### 期待結果（観測可能なチェック）

| # | チェック | 観測方法 |
|---|---|---|
| 3-1 | 全 must-fix に意図アンカー（対応する受け入れ条件・invariant）と ID 付き有限 inventory・閉じる条件が付き、「全〜」「〜など」だけの閉じる条件が無い | round 1 の review_result |
| 3-2 | 再レビューが inventory ID 単位の CLOSED / PARTIAL / NEW 判定のみで、同一指摘の要求拡張が無い | round 2 の review_result |
| 3-3 | 設計レベルの欠陥が designer に差し戻され、修正に新 layer・新規サブシステムの追加を要する場合は stage-out（default-off 隔離 + follow-up issue 提案）が選ばれる | 対応表と issue コメント |
| 3-4 | 環境依存挙動への指摘が targeted テスト 1 本 + deploy 後確認の証明 tier で閉じ、flaky テストの反復修正が発生しない | 検証台帳と commit 履歴 |
| 3-5 | 意図アンカーを付けられない指摘が must-fix にならず follow-up 提案に分類され、nit が「対応不要（記録のみ）」のまま修正 diff に混入しない | review_result・対応表・diff |
| 3-6 | HANDOFF の発火が「収束停滞（未解消 must-fix 数が減らない・PARTIAL 反復・inventory 外拡張の継続）」または「人間専権」に限られ、判定根拠が計測ログに記録され、最終コメントが承認と区別されている | 計測ログと最終コメント |
| 3-7 | round が新 cycle に誤分類されず、収束している限り round 数による打ち切りが発生しない（round ごとの未解消 must-fix 数の推移が記録されている） | 計測ログの cycle 表（トリガー記載付き） |
| 3-8 | designer / worker の規模申告が設計・完了報告・計測ログに記録され、自動停止に使われていない。cycle 表に時間 4 区分と実行対象の skill 版（commit SHA）が記録されている | 設計・完了報告・計測ログ |
| 3-9 | 共有ヘルパー変更が持ち込んだ既存 API の regression（受け入れ条件に明記されていないもの）が、reviewer で暗黙の非退行 invariant にアンカーされて must-fix になり、main の対応表で「今回必須」に裁定され（「新機能のゴール達成済み」を理由に follow-up へ降格されない）、修正 evidence で閉じる | review_result の意図アンカー・main の対応表・修正 evidence |

## 実行結果の証拠

実行のたびに追記する。実行前に記入しない。

| 実行日 | 対象スキル改訂 | シナリオ | 充足 | 生成物の所在 | 備考 |
|---|---|---|---|---|---|
| 2026-07-13 | 設計契約 v2 導入時（branch `agent/21-pipeline-contract-redesign`）実行 1 回目 | 族 1（kobato fixture） | 1-1 ✓ / 1-2 ✓ / 1-3 ✓ / 1-4 ✓ / 1-5 △ / 1-6 ✓ | [forward-test-evidence-2026-07-13.md](forward-test-evidence-2026-07-13.md) §1-2 | 1-5: スコープ判定の機構は動作したが、fixture の各ファイルが小さく「網羅可能」判断となり分割提案は未発火 → 実行 2 回目で解消 |
| 2026-07-13 | 同上・実行 1 回目 | 族 2（tsugumi fixture） | 2-1 ✓ / 2-2 ✓ / 2-3 ✓ / 2-4 ✓ / 2-5 未実施 / 2-6 ✓ | [forward-test-evidence-2026-07-13.md](forward-test-evidence-2026-07-13.md) §3 | 2-5 と reviewer 契約は実行 2 回目で検証 |
| 2026-07-13 | 同上・実行 2 回目 | 族 1 拡張（kobato + Web/OpenAPI/runbook/MCP、issue スコープ拡大） | 1-5 ✓ | [forward-test-evidence-2026-07-13.md](forward-test-evidence-2026-07-13.md) §1 | designer が客観 signal（7 layer / migration / security / consumer 6+ / DB hot path）を根拠に「網羅不能」と判定し、単独 merge・deploy 可能な 5 stage 分割案 + 元 DoD を保持した stage mapping を生成 |
| 2026-07-13 | 同上・実行 2 回目 | 族 2（owner 回答で高リスク前提を解消した再開 run） | 2-5 ✓ / reviewer 契約 ✓（G4 scope 検査・2 パス・review point matrix・G5） | [forward-test-evidence-2026-07-13.md](forward-test-evidence-2026-07-13.md) §3-4 | main → worker → G3 → reviewer 2 パス → round 2 APPROVED → material rebase で cycle 2 → 統合レビュー → migration の unchecked を人間回答で checked に再判定してから G5 成立、を停止条件の迂回なしで完走 |

### 2026-07-13 実行の詳細

- ハーネス: fixture 2 リポジトリとスキル bundle の export を Agents リポジトリ外の一時ディレクトリに配置。test agent（designer / falsifier / worker）には raw fixture・コンテキストノート・契約 reference の絶対パスのみを渡し、本ドキュメント・期待結果・「検証中」の事実は伝えていない。全 test agent は fresh thread で実行。照合と本記録は生成物完成後に evaluator が実施。
- 族 1: designer が事実表で config 100,000 / DB 保存値 1,000,000 / 表示値の三重不一致を正本分離し（1-1）、risk-reducing 経路（STOP / TP / manual close）を新 gate に通さない設計を選択、状態遷移 matrix で全状態の risk-reducing 列が success であることを確認した（1-2）。consumer matrix 4 行（1-3）、migration → deploy の順序制約と GRANT を含む deployment 手順（1-4）を生成。main の構造判定（6 layer / migration / security / 複数 consumer 該当）で独立 falsifier を必須発動し、falsifier は designer が「設計修正済み」と宣言した FOR UPDATE 直列化に対して insert 先行 interleaving の反例を提示、境界 timestamp・rollback 中の silent 混合・復旧経路の不在・見落とし前提 4 件も検出した（1-6。anchor された自己申告を独立反証が破る、という導入目的どおりの挙動）。
- 族 2: designer が reconciler の例外握りつぶしを call graph の終端（hardHaltSweep / reconcile / markSuccessfulPass の skip）まで追跡し、audit 障害中に保護処理の新規発動が止まる帰結を（高リスク・要人間確認）として明示（2-1）。audit failure と send 例外の複合時は AuditWriteException 優先 + 元例外 suppressed と決定（2-2）。non-functional contract は既知（出典）/ 推定（根拠）/ 未測定（測定方法・fail-safe 上限・deploy 後確認）で分類（2-3）。NoopAuditSink 既定値の削除と全 entrypoint の明示配線を設計し、worker 実装後の grep で定義行のみ残存を確認（2-4）。worker の完了報告は evidence matrix 形式で、production call path 列は 3 entrypoint からの実経路、検証台帳は validation scope 付き・SHA 一致で G3 受理（2-6）。
- 高リスク未検証前提プロトコル: 両 designer とも high リスク未検証前提を仮決めせず列挙して返した（族 2 では「既存 DB スキーマの additive 列追加可否」等 3 件）。実運用の自走ではこれらは 3 分岐の停止条件に該当する。

### 2026-07-13 実行 2 回目の詳細

- 族 1 拡張（スコープ分割の発火）: fixture に Web コンソール 3 画面・OpenAPI・deploy runbook・分析 MCP を追加し、issue のスコープを epoch 化 + 評価コンソール全面改修 + OpenAPI 契約 + role 追随 + 運用手順に拡大。fresh designer は「1 worker / 1 reviewer では網羅不能」と判定し、客観 signal を根拠に記録した上で、各 stage が単独で merge・deploy 可能かつ backward-compatible な 5 stage 分割案と、元の受け入れ条件を変更しない stage mapping（各条件 → stage 番号）を生成した。
- 族 2（実運用パイプラインの完走）: 実行 1 回目で停止条件に該当した高リスク未検証前提 3 件に owner 回答（列追加可・DB 接続可・保護停止の帰結受容）を与えて再開。main の G4（SHA 一致 + validation scope の tier 適合）→ reviewer round 1 の 2 パス（should 1 / nit 4、review point matrix でベクトル 5 = migration 順序を unchecked と申告）→ worker の cluster 修正と G3 受理 → round 2 APPROVED → base への material overlap コミットに対する rebase（conflict 解消 + affected 検証 + 最終 HEAD full 検証）→ cycle 2 / round 1 として統合レビュー → migration 順序への owner 回答（migration 適用 → rolling deploy の順序を pipeline で担保、NULL 許容列で旧コード共存）を受けて reviewer がベクトル 5 を checked に再判定（cycle 2 / round 2）→ G5（safety / migration / security の unchecked ゼロ・最終 HEAD full 成功・description 材料同期）の順で、停止条件の迂回なしに完走した。safety / migration / security の unchecked は人間確認事項への転記では閉じず、人間回答による checked 再判定または分割だけが解消手段であることも、この run で行使された。
- cycle 表（族 2 run）: cycle 1 = トリガー: 初回実装 / rounds 2 / must-fix 0・should 1・nit 4 / origin: internal-r1 / wall-clock 約 40 分・compute: unknown。cycle 2 = トリガー: material rebase（+ 人間回答による unchecked 解消）/ rounds 2 / nit 1 / origin: internal-r1 / wall-clock 約 20 分 + 回答待ち・compute: unknown。round 番号は cycle 開始でリセットされ、rebase は同一 round に混入しない。
- 未対応 nit の扱い: cycle 2 nit-1（非 default maxAttempts の境界テスト）は任意対応として対応表に記録し、残存事項扱い。
