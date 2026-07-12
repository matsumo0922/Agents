# forward test 実行証拠(2026-07-13)

`docs/pipeline-forward-tests.md` の 2026-07-13 実行(対象: branch `agent/21-pipeline-contract-redesign` のスキル改訂)で生成された artifact の sanitized 抜粋。fixture 全文と test agent の transcript は含めない(汚染防止ハーネスの生成物のうち、期待結果の検証に必要な最小限だけを残す)。

## 1. 族 1 拡張: スコープ判定と staged PR 分割(チェック 1-5)

designer(fresh context)が生成した「## 設計」の該当セクション抜粋:

> ### スコープ判定
>
> 1 worker / 1 reviewer では網羅不能と判断する。客観 signal: 跨る layer 7(DB schema / domain / API / Web / batch / MCP / docs)、schema migration あり(additive・可逆)、security boundary 変更あり(readonly role への GRANT 追加)、consumer 6+(API・Web 3 画面・Kotlin UI・batch・MCP)、DB hot path 該当(全 write の唯一の経路への stamp)。
>
> staged PR 分割案(各 stage は単独で merge・deploy 可能かつ backward-compatible):
> - Stage 1: epoch 基盤 — migration(テーブル 2 + 列追加 + seed)、EpochService、write stamping、切替 CLI、runbook。旧 API は新テーブルを参照しないため単独 deploy 可
> - Stage 2: 評価 API 契約 — API の epoch 対応、OpenAPI、web 型、UI baseline 修正。応答 field は additive のため旧 web と共存可。依存: stage 1
> - Stage 3: 週次レポート — epoch 別出力、一覧 API、旧形式互換。依存: stage 1
> - Stage 4: Web コンソール — 3 画面の epoch UI。依存: stage 2, 3
> - Stage 5: MCP + GRANT — ツール追加と GRANT(消費者の登場と同じ PR で権限を広げる)。依存: stage 1
>
> 受け入れ条件の stage mapping(元の受け入れ条件は変更せず保持):
>
> | 受け入れ条件 | stage |
> |---|---|
> | 全応答に epoch・silent 混合なし | API: 2 / レポート: 3 / Web: 4 / MCP: 5 |
> | OpenAPI・web 型・API 一致 | 2, 3 |
> | 切替 gate + 監査イベント | 1(画面表示は 4) |
> | 既存の残高・履歴 row を書き換えない | 1 |
> | runbook の順序制約 | 1 |
> | ./verify.sh 成功 | 全 stage |
>
> non-goal へ落とす受け入れ条件: なし。

## 2. 族 1: 独立 falsifier の反証結果(チェック 1-2 / 1-6)

main の構造判定(cross-layer 6 layer + migration + security + 複数 consumer 該当)で必須発動した clean context falsifier の falsification_result 抜粋。**designer が「設計修正済み」と宣言した対策そのものへの反例**を含む:

> - 反例 1(V2 / FOR UPDATE 直列化の片方向性・重大): 設計は「account row の FOR UPDATE lock で writer transaction と直列化」により不変条件「trade が epoch を跨がない」を担保すると主張する。しかし writer は transaction 内で insertOrder を先に実行し、account row の lock を取るのは後段の updateCash 時点である。interleaving: (1) writer tx 開始 → insertOrder 実行(未 commit)→ (2) 切替側が FOR UPDATE 取得(writer は account row 未接触で block されない)→ (3) READ COMMITTED では未 commit の entry が count に見えず 0 → (4) 切替 commit → (5) writer が updateCash を通過して commit。境界を跨ぐ open position が成立する。設計の「修正済み」宣言は不成立。
> - 反例 2(V2 / 境界値): 半開区間 + 同一 timestamp 切替の下で、決済の executed_at が切替時刻と一致した場合に旧 epoch 内で完結した trade が新 epoch に帰属し得る(時刻源が未規定)。
> - 反例 3(V5 / rollback 後の silent 混合): 「rollback はイメージ切り戻しのみで無害」は切替 0 回の場合のみ成立。切替後に旧 app へ戻すと旧 baseline で全 trade を混合表示し、受け入れ条件が rollback 中に再発する。
> - 反例 4(V3 / 復旧経路): epoch 0 件状態を自己修復せず、matrix が復旧を委ねる migration の再実行可能性(冪等性)が設計に未記載。
> - 見落とし前提 4 件(closed trade 導出の実在、単一時刻源、migration 冪等性、「事実」の確認方法がコメント由来で実 DB 未参照)。

## 3. 族 2: reviewer round 1 の 2 パスレビュー(チェック 2-6 / reviewer 契約)

### review_result(cycle 1 / round 1)要約

- G4: 台帳 SHA == HEAD、scope: full(初回実装の要求 tier)→ 通過
- 結果: must-fix 0 / should 1 / nit 4
- should-1: 「request(symbol) が try 内で評価され、構築失敗が実 attempt として監査記録される」— 不変条件「実 send 数 == event 数」を破る反例(pass 1 ベクトル 2)。閉じる条件付き
- pass 1: fetchTicker の全 4 呼び出し元(CLI / MCP / web routes / reconciler)を終端まで追跡、握りつぶして値を使う経路なし。fail-closed が保護処理を止める点は owner 受容と突合
- pass 2: evidence matrix 全行を実コード・実テストと突合(件数記載差異 1 件を nit として検出)
- review point matrix: 反証 5 ベクトル + 実装観点の 11 行。ベクトル 5(migration / deploy 順序)のみ unchecked(repo 外で検証不能)

### review_result(cycle 1 / round 2)要約

- 対応確認: should-1 / nit-1 / nit-3 の閉じる条件成立をコードで確認、nit-2 / nit-4 の受容は妥当
- 修正コミット固有欠陥クラス: 置換等価性(時計統一・単位維持・リネーム完全)・新規境界の持ち込みなし
- 結果: APPROVED(must-fix / should / nit 0)

### review_result(cycle 2 / round 1)要約 — material rebase の統合レビュー

- トリガー: base の「retry 回数の param 化」コミットとの conflict 解消を伴う rebase(material overlap)
- G4: 台帳 SHA == HEAD、scope: affected + 同 HEAD の full → 通過
- 確認: conflict 解消の両立性(base 側の param 化を取り込みつつ、監査必須配線の意図を維持。base 側が持っていた無記録 default の復活を正しく破棄)/ 不変条件「実 send 数 == event 数」が retry 回数 param に非依存 / rebase 固有欠陥(marker・二重適用・取り残し・全 10 呼び出し箇所のシグネチャ)なし
- 結果: APPROVED + nit 1(非 default 値の回帰テスト、任意対応)

### review_result(cycle 2 / round 2)要約 — unchecked の解消再判定

- 契約明確化(safety / migration / security の unchecked は転記では閉じない)を受け、owner 回答「migration 適用 → rolling deploy の順を pipeline で担保。列は NULL 許容で旧コードと共存可」に基づきベクトル 5 を **unchecked → checked** に再判定
- 根拠: 回答が失敗モード(列より先にコードが本番到達)の発生条件を運用上排除し、旧コード共存の残余懸念も NULL 許容で閉じることを、設計の deployment 決定・スコープ外宣言と突合して確認
- 最終 review point matrix: 13 行中 checked 12、unchecked 1(PR description 形式 — fixture に PR が無いため対象外。safety / migration / security に属さず APPROVED を妨げない)
- 結果: APPROVED(G5 判定可)

## 4. 検証台帳と cycle 表、G5 判定(族 2 run)

検証台帳(抜粋、scope 付き):

| コマンド | 結果 | HEAD | scope |
|---|---|---|---|
| ./verify.sh | ok | 初回実装 HEAD | full(初回実装完了) |
| ./verify.sh | ok | レビュー修正 HEAD | レビュー修正(compile + targeted 相当) |
| ./verify.sh | ok | rebase 後 HEAD 7737445 | affected(rebase、監査テストとの整合をコード読みで確認) |
| ./verify.sh | ok | 同 7737445 | full(最終 APPROVED 前) |

cycle 表:

| cycle | トリガー | rounds | must-fix / should / nit | finding origin | wall-clock | compute |
|---|---|---|---|---|---|---|
| 1 | 初回実装 | 2 | 0 / 1 / 4 | internal-r1 | 約 40 分 | unknown |
| 2 | material rebase(+ 人間回答による unchecked 解消) | 2 | 0 / 0 / 1 | internal-r1 | 約 20 分 + 回答待ち | unknown |

- compute time は依存関係付きの実測手段が無いため、規則(推測値を確定値として記録しない)に従い unknown と記録。
- G5 判定: (1) 最終 matrix に safety / migration / security の unchecked なし(ベクトル 5 は人間回答で checked に解消) (2) 検証台帳の最終エントリ = 最終 HEAD の full 成功 (3) PR description 更新材料が最終 HEAD と同期(fixture に実 PR が無いため材料の受領まで) → 成立。
- 残存事項: cycle 2 nit-1(非 default retry 回数の回帰テスト)は任意対応として未対応のまま記録。
