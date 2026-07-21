---
name: falsify
description: "設計・提案・実装方針に対して、書いた本人以外の clean context が反例を探す独立反証スキル。反証 5 ベクトル・blocking の処置・高リスク未検証前提の扱い・価値判断をユーザーに確定させる質問作法を定める。Use when the user asks to falsify a design or proposal, run an independent falsification, find counterexamples, 反証して, 設計を反証して, 提案の穴を独立に探して, or when issue-pr-autopilot reaches its falsification gate."
---

# Falsify

設計、提案（OpenSpec の proposal.md + delta spec を含む）、実装方針に対して、書いた本人以外の clean context が反例を探す。書き手の自己承認では見つからない欠陥を、独立した視点で実装前に潰すことが目的。対話セッションで `/opsx:propose` の成果物を単体で反証する用途と、issue-pr-autopilot の反証ゲートから呼ばれる用途の両方を持つ。

dig との対称構造として、dig はユーザーとの対話による設計前の反証を、falsify は clean context による設計後の独立反証を担う。

## 開始条件

- 反証対象が読める形で存在する（proposal.md + delta spec、設計ドキュメント、会話中に明文化された実装方針など）
- 対象が依拠するリポジトリとドキュメントを falsifier が読める

## 発動判定

cross-layer / safety / migration / security / 複数 consumer / DB hot path のいずれかに触れる設計は独立反証を必須とする。該当しない場合は書き手の自己反証でよい。ただし次の 2 点に従う。

- 自己反証で blocking が 1 件でも出たら独立反証に昇格し、修正後の解消確認も独立 falsifier が行う。自分の修正を自己承認して blocking を閉じることはできない
- 発動判定は書き手自身にさせない。呼び出し側（ユーザーまたはオーケストレーター）が判定し、迷ったら発動する

## falsifier の起動

- falsifier は clean context のサブエージェントとして起動し、反証対象とリポジトリ（読み取り専用）だけを渡す。書き手の弁明、検討の経緯、会話履歴は渡さない
- モデルは clean context の強モデルを割り当てる。Codex 環境では Codex 自身のサブエージェント（spawn）で clean context の falsifier を立てる。falsify の本質は「書き手と別の clean context」であり、Claude であることではない

## falsifier の職掌

falsifier は検証と列挙だけを行い、処置の決定はしない（処置は設計の書き手の責務）。

1. 反証 5 ベクトルによる反例の列挙
2. 設計が「非該当」と宣言した確認事項の妥当性検証（宣言が誤っていないか）
3. スコープ判定の妥当性（1 実装者 / 1 レビュアーで網羅可能か。受け入れ条件に紐付かない拡張が混入していないか）
4. 高リスク未検証前提の見落とし（「事実」とされた値に確認方法が無いものはないか。暗黙の前提はないか）
5. レビュー可能性と実装可能性（人間が 1 本の PR としてレビューできる規模か。実装者が設計とリポジトリだけで完遂できるか）

## 反証 5 ベクトル

反例は「この入力とこの状態で、こう誤る」の形で書く。

1. **production fact と仮定の不一致**：設計が依拠する値は config / DB 保存値 / runtime 値 / 表示値のどの正本と照合されたか。複数の所在で値が食い違う可能性を「一致している」と暗黙に仮定していないか
2. **不変条件を破る反例**：宣言された invariant が成立しない操作列、並行実行、境界値
3. **failure 後の downstream state**：例外、拒否、null を導入したとき、受け側が握りつぶして後続処理全体を skip しないか。伝播の終端まで追う
4. **safety direction**：新しい gate や validation は risk-increasing な操作だけを塞いでいるか。risk-reducing な操作（損切り、復旧、rollback、手動介入）まで塞いでいないか。「全部拒否」は安全ではない
5. **負荷、容量、upgrade path**：hot path の同期 I/O、unbounded query、migration と provisioning の順序、旧バージョンとの共存

## 返却形式

反例ごとに、ベクトル番号 / severity / scope / 提案 disposition / 内容 / 根拠となるコード箇所を列挙して返す。反例ゼロの場合は「各ベクトルで探索した結果反例なし」と明記する（無言の省略を認めない）。

## blocking の判定

受け入れ条件を破る / 宣言 invariant を破る / 証明可能な correctness 欠陥 / データ損失や破損 / race / 互換性や API の破壊 / security・privacy / safety・migration boundary の欠陥は、受け入れ条件に明記されていなくても blocking とする。迷う場合は blocking に倒す。

scope（introduced / worsened / pre-existing-out-of-scope）は severity と独立の軸であり、scope を理由に severity を下げない。

## blocking の処置 4 ルート

書き手の「受容 + 理由」だけでは blocking を閉じられない。次のいずれかで閉じる。

1. **設計修正**：修正のうえ、同じ falsifier が解消を再確認する
2. **保証の縮退**：invariant を観測可能な弱い保証へ狭め、狭めた分を residual risk として明記する。縮退後も falsifier が再確認する
3. **stage-out**：対策を後続 stage / 別 change に分離し、該当機能を default-off / feature flag で隔離する。隔離により反例の前提が崩れることを falsifier が確認する
4. **人間判断**：要件やリスク許容の明示的変更。対話中は構造化質問で、自走中は停止して issue へ質問する

対策が新しい機構（新規サブシステムや新 layer）を要する場合、機構を足す前に stage-out で閉じられないか必ず検討する（設計の膨張は下流の実装、レビュー、検証をすべて遅くする）。security やデータ破壊の反例は縮退だけでは閉じられず、隔離または人間判断を併用する。

## 高リスク未検証前提のプロトコル

high リスクの未検証仮定は「agent が勝手に仮決め」で通過させない。

1. まず書き手自身がコード、保存状態、運用経路（migration 履歴、設定、既存テスト）から検証を試みる
2. 検証不能で対話中なら、構造化質問でユーザーに確定させる
3. 検証不能で自走中なら 3 分岐する
   - 実装方式、不可逆 migration、安全性、permission 境界を左右する → 停止し、issue に質問を投稿して人間の回答後に再開する
   - reversible かつ additive で、未確定判断を含まない stage を切り出せる → その stage だけ進行する
   - 既存状態を維持するだけで変更挙動に影響しない場合のみ → fail-safe 側（既存状態を変更しない側）を仮決めし、（高リスク・要人間確認）マークを付けて進行する
4. マークされた前提は reviewer の必須反証対象になり、PR の「人間に確認してほしいこと」へ必ず転記する

## 帰属タグと質問の作法

設計上の各決定には 3 区分の帰属タグを付ける。OpenSpec の成果物（proposal.md / design.md）内の記法として埋め込む。

- **（ユーザー確認済み）**：質問や議論でユーザーが確定した決定
- **（agent 仮決め）**：agent が独断で決めた low リスクの判断。PR の「人間に確認してほしいこと」へ転記する
- **（高リスク・要人間確認）**：上記プロトコルを経て仮決めで進行した決定。reviewer の必須反証対象とし、人間確認事項へ必ず転記する

価値判断（リスク許容、運用方針、トレードオフの選好）はユーザー専権とする。構造の判断（どの層に置くか、どう分割するか）は agent が決めてよい。質問は価値判断に絞り、どの選択肢を選んでも設計が変わらない質問はしない。

## 終了条件

次のいずれかで終了する。

- **通過**：未解消の blocking 反例がゼロ（falsifier が各ベクトルの探索完了と解消を確認済み）。non-blocking の反例は residual risk として対象ドキュメントに記録する
- **人間判断待ち**：処置ルート 4 に入った論点を明示して停止する

十分の基準は次のとおり。5 ベクトルを各 1 周探索して blocking が出なければそこで終える。non-blocking の反例を磨き続けない。ただし探索の切り上げを、見つけた反例の検証と根拠コード箇所の確認より優先しない。

## 不変条件

1. falsifier は反例の列挙と解消確認だけを行い、処置を決めない
2. 書き手は自分の blocking を自己承認で閉じられない
3. 価値判断はユーザー専権であり、agent が仮決めした場合は帰属タグで可視化する
