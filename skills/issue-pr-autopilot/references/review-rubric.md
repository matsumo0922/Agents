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

レビューを始める前に、検証台帳の最終エントリの SHA と worktree HEAD の一致を read-only 操作（`git rev-parse HEAD` 等）で確認する。不一致ならレビューせず main agent に差し戻す。build / test / lint は実行しない（検証台帳を信頼する）。

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

review_result に、全 review point（反証 5 ベクトル + pass 2 の観点 + 設計の「レビュー観点」の各項目）の checked / unchecked を返す。

```text
<review_point_matrix>
| review point | 結果 | 備考 |
|---|---|---|
| 反証ベクトル 1〜5（各行） | checked / unchecked | unchecked は理由必須 |
| call graph 追跡 | checked / unchecked | |
| evidence 突合 | checked / unchecked | |
| 設計のレビュー観点の各項目 | checked / unchecked | |
</review_point_matrix>
```

- unchecked には必ず理由を付ける（実機が無い、負荷は観測不能、等）。
- **safety・migration・security に属する review point が unchecked のまま APPROVED を返さない。** 該当する場合は追加確認を行うか、main に「分割または人間確認事項化が必要」と返す。
- unchecked は main が PR description の「人間に確認してほしいこと」へ転記する。

## evidence matrix 突合基準

worker の evidence matrix の各行について:

- **実装箇所**: 記載された file / シンボルが実在し、条件の実装と対応しているか。
- **production call path**: 記載された経路が実在するか。本番エントリポイント（main / route / worker 起動）から実際に到達可能か grep で確認する。「テストからのみ到達」の行は、その理由が妥当か判断し、妥当でなければ production wiring 不足の must-fix にする。
- **証明するテスト名**: テストが実在し、条件が主張する境界を実際に検証しているか（手組み入力だけで通る unit テストが本番配線の代わりにされていないか）。
- 記載と実体が食い違う行は、その行の条件を「未充足」として must-fix にする。

## severity と閉じる条件

- severity 基準: must-fix = 受け入れ条件違反、または発生条件を特定できる証明可能な欠陥（データ破壊・レース・セキュリティ・互換性・情報露出・設計欠陥）。should = 受け入れ条件は満たすが品質・保守性に実害がある。nit = 好みや微細な改善。
- 各 must-fix には「閉じる条件」を必ず書く: 修正後に成立しているべき不変条件と、テストが証明すべき境界。
- must-fix を 1 件見つけたら問題クラスとして一般化し、同じクラスの他のインスタンス（他の層・経路・出力先）を grep と call graph 追跡で列挙して、確認した同根 call site 一覧とともに 1 つの指摘グループとして報告する。
