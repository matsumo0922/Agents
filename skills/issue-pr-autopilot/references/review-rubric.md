# review rubric: reviewer round 1 の 2 パス手順

issue-pr-autopilot の reviewer が round 1 で使う。設計形式の定義は design スキルの `references/design-contract.md`、反証 5 ベクトルの定義は同 `references/falsifier-rubric.md` を参照する（パスは main agent の指示に含まれる）。

## 目次

1. [開始前チェック（G4）](#開始前チェックg4)
2. [pass 1: 設計反証](#pass-1-設計反証)
3. [pass 2: 実装レビュー](#pass-2-実装レビュー)
4. [review point matrix の形式](#review-point-matrix-の形式)
5. [evidence matrix 突合基準](#evidence-matrix-突合基準)
6. [severity と閉じる条件](#severity-と閉じる条件)

## 開始前チェック（G4）

レビューを始める前に、検証台帳の最終エントリについて次の 2 つを確認する。いずれかを満たさない場合はレビューせず main agent に差し戻す。build / test / lint は実行しない（検証台帳を信頼する。SHA 確認は `git rev-parse HEAD` 等の read-only 操作のみ）。

1. SHA が worktree HEAD と一致する。
2. validation scope が現在の phase に要求される tier を満たす: 初回レビュー = full / レビュー修正後の再レビュー = compile + 修正対象の targeted tests 以上 / rebase 後 = affected（overlap なしなら compile）以上 / 仮承認（APPROVABLE_PENDING_FULL）= targeted 以上で可（full は仮承認後に worker が 1 回だけ実行する）。SHA が一致していても scope が不足する entry（広い変更後の compile-only 等）はゲートを通さない。

## pass 1: 設計反証

実装ではなく設計そのものを疑う。ノートに転記された設計に対して次を確認する。

1. **反証 5 ベクトル**（falsifier-rubric.md の定義に従う）: production fact と仮定の不一致 / 不変条件を破る反例 / failure 後の downstream state / safety direction / 負荷・容量・upgrade path。設計フェーズの `### 反証` セクションが「反例なし」でも鵜呑みにせず、実装されたコードを証拠として再探索する。
2. **条件付き matrix の発動判定**: 非該当宣言（「状態遷移 matrix: 非該当」等）が誤っていないか。実装された diff が発動条件に触れているのに matrix が無い場合は設計欠陥。
3. **（高リスク・要人間確認）マークの前提**: マークされた各前提を、コード・保存状態・テスト fixture から反証できないか試みる。

設計自体の欠陥は **「設計欠陥」ラベル付きの must-fix** として返す。設計欠陥の修正は worker ではなく designer / architect が行うため、通常の must-fix と区別できるようにする。

## pass 2: 実装レビュー

従来の review points（受け入れ条件 / バグ・エッジケース・レース・互換性・データ破壊・セキュリティ / リポジトリ規約 / テストの妥当性 / ドキュメント影響 / PR description 形式 / 設計整合 / 変更固有のレビュー観点）に加えて、次を必ず行う。

- **call graph 追跡**: 変更した gate・例外・戻り値について、全呼び出し元と受け側を grep / call graph で列挙し、受け側が新しい挙動（例外・null・拒否）を安全に処理することを確認する。「投げる側だけ直して受け側を見ない」レビューを禁止する。
- **evidence matrix 突合**: worker の evidence matrix の各行を実コード・実テストと突合する（基準は後述）。
- **修正コミット固有の欠陥クラス**（round 2 以降の再レビューでも適用）: 修正が新規に持ち込んだ cache・lock・transaction 境界・置換前後の等価性（消えた LIMIT、bind されない変数、二重 parse 等）を確認する。

## review point matrix の形式

review_result に、全 review point（反証 5 ベクトル + pass 2 の観点 + 設計の「レビュー観点」の各項目）の checked / unchecked / isolated_unverified を返す。

```text
<review_point_matrix>
| review point | 結果 | 備考 |
|---|---|---|
| 反証ベクトル 1〜5（各行） | checked / unchecked / isolated_unverified | unchecked は理由必須 |
| call graph 追跡 | checked / unchecked / isolated_unverified | |
| evidence 突合 | checked / unchecked / isolated_unverified | |
| 設計のレビュー観点の各項目 | checked / unchecked / isolated_unverified | |
</review_point_matrix>
```

- 各 review point の結果は checked / unchecked / **isolated_unverified** の 3 状態。unchecked には必ず理由を付ける（実機が無い、負荷は観測不能、等）。
- **isolated_unverified**: 機能の正しさは未検証だが、default-off / feature flag による隔離を確認した状態。隔離の確認と機能の検証は別物なので checked にはしない。この状態にできるのは次の 3 条件をすべて reviewer が確認した場合だけ: (1) 実効設定が fresh install・既存環境の両方で default-off である (2) 別経路（既存設定・環境変数・他機能からの間接呼び出し）から有効化されない (3) 有効化には別 PR または明示的な検証 gate が必要である。確認内容と有効化条件を人間確認事項へ転記する。
- **safety・migration・security に属する review point が unchecked のまま仮承認（APPROVABLE_PENDING_FULL）を返さない。** PR description の「人間に確認してほしいこと」への転記は未確認事項の可視化であって unchecked の解消ではない。閉じる方法: (1) 人間の回答または観測可能な証拠を受けて reviewer が checked と再判定する (2) 該当範囲を分割して本 PR のスコープから除外する (3) 上記 3 条件を確認して isolated_unverified にする。いずれも成立しない場合は仮承認を保留し、main に「人間回答が必要」「分割が必要」「隔離が必要」のいずれかを返す（main の終了状態は HANDOFF になる）。
- safety・migration・security 以外の unchecked は仮承認を妨げない。main が PR description の「人間に確認してほしいこと」へ転記する。

## evidence matrix 突合基準

worker の evidence matrix の各行について:

- **実装箇所**: 記載された file / シンボルが実在し、条件の実装と対応しているか。
- **production call path**: 記載された経路が実在するか。本番エントリポイント（main / route / worker 起動）から実際に到達可能か grep で確認する。「テストからのみ到達」の行は、その理由が妥当か判断し、妥当でなければ production wiring 不足の must-fix にする。
- **証明するテスト名**: テストが実在し、条件が主張する境界を実際に検証しているか（手組み入力だけで通る unit テストが本番配線の代わりにされていないか）。
- 記載と実体が食い違う行は、その行の条件を「未充足」として must-fix にする。

## severity と閉じる条件

- **意図アンカー**: 各指摘に「issue の受け入れ条件・設計 invariant のどれを守るための指摘か」の紐付けを付ける。must-fix はアンカー + 閉じる条件が揃って初めて成立する。アンカーを付けられない指摘は内容の正しさに関わらず must-fix にせず、follow-up 提案として分類して報告する。
- severity 基準: must-fix = 受け入れ条件違反、または発生条件を特定できる証明可能な欠陥（データ破壊・レース・セキュリティ・互換性・情報露出・設計欠陥）。should = 受け入れ条件は満たすが品質・保守性に実害がある。nit = 好みや微細な改善で、**既定処置は「対応不要（記録のみ）」**。
- 各 must-fix には**有限の「閉じる条件」**を必ず書く: sweep で確認した対象（call site / failure point / 出力先）を列挙して ID を振った inventory と、各 ID の修正を証明する観測（テスト名またはコマンド）。「全〜」「〜など」の開いた表現だけで閉じる条件を書かない。inventory に含めなかった経路は閉じる条件に含まれない（後から見つけた場合は reopen ではなく新規指摘として扱う）。
- must-fix を 1 件見つけたら問題クラスとして一般化し、同じクラスの他のインスタンス（他の層・経路・出力先）を grep と call graph 追跡で列挙して、1 つの指摘グループとして報告する。この sweep で確認した一覧がそのまま閉じる条件の inventory になる。
- 再レビューでは各 must-fix を inventory ID 単位で CLOSED / PARTIAL（未充足 ID を列挙）/ NEW と判定し、同一指摘の要求を拡張しない。
