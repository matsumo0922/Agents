# falsifier rubric: 設計反証パスの手順

設計確定前の反証パスで使う。独立反証者（falsifier サブエージェント）と、自己反証時の architect / designer が読む。設計形式の定義は `design-contract.md` を参照する。

## 職掌

falsifier は次の 4 つを検証し、結果を列挙して返す。**処置の決定と設計への反映は行わない**（architect / designer の責務）。

1. 反証 5 ベクトルによる反例の列挙
2. 条件付き matrix の発動判定の妥当性（非該当宣言が誤っていないか）
3. スコープ判定の妥当性（1 worker / 1 reviewer で網羅可能という判断は成立するか。客観 signal と整合するか）
4. high リスク未検証前提の見落とし（事実表に書かれた「事実」に確認方法が無いものはないか。仮定表に載っていない暗黙の前提はないか）

## 反証 5 ベクトル

各ベクトルについて、設計を「破る」具体的な反例を探す。反例は「入力・状態 → 誤った結果」の形で書く。

1. **production fact と仮定の不一致**: 設計が依拠する値・挙動は、config / DB 保存値 / runtime 値 / 表示値のどの正本と照合されたか。複数の所在で値が食い違う可能性を、設計は「一致している」と暗黙に仮定していないか。
2. **不変条件を破る反例**: 設計が宣言する不変条件（「100% 付与する」「必ず監査される」等）が成立しない操作列・並行実行・境界値はないか。
3. **failure 後の downstream state**: 例外・拒否・null を導入した場合、その受け側（呼び出し元・consumer・後段の処理）はどう振る舞うか。受け側が握りつぶして保護処理・後続処理全体を skip しないか。伝播の終端まで追う。
4. **safety direction**: 新しい gate・validation・fail-closed は、risk-increasing な操作だけを塞いでいるか。risk-reducing な操作（損切り・決済・復旧・rollback・手動介入）や復旧経路まで塞いでいないか。「全部拒否」は安全ではない。
5. **負荷・容量・upgrade path**: hot path の同期 I/O、unbounded query / materialization、行数増加、二重 parse、integer overflow、migration と provisioning の順序、旧バージョンとの共存。non-functional contract の数値分類（既知 / 推定 / 未測定）は正しいか。

## 実施形態

- **独立反証（falsifier サブエージェント）**: 変更が客観条件リスト — cross-layer 変更 / safety / migration / security / 複数 consumer / DB hot path — のいずれかに該当する場合に必須。該当判定は main agent が行う（architect / designer 自身に判断させない。迷ったら発動する）。falsifier は clean context で spawn し、設計ドラフト・本 rubric・対象リポジトリ（読み取りのみ）だけを受け取る。台帳の分析過程は受け取らない。モデルは architect と同じ最上位ティア高 effort とする。
- **自己反証**: 客観条件リストのいずれにも該当しない設計では、同一 architect / designer が別ターンで本 rubric に従って自己反証する。

## 返却形式

```text
<falsification_result>
- 反例: <ベクトル番号 / blocking または non-blocking / 反例の内容（入力・状態 → 誤った結果）/ 根拠となるコード箇所> を列挙。なければ「各ベクトルで探索した結果反例なし」
- matrix 発動判定: <条件付きセクションごとに 妥当 / 誤り + 理由>
- スコープ判定: <妥当 / 誤り + 理由>
- 見落とし前提: <仮定表に無い暗黙の前提、確認方法の無い「事実」。なければ「なし」>
</falsification_result>
```

**blocking 判定の基準**: 受け入れ条件を破る反例 / 設計が宣言した invariant を破る反例 / safety・migration・security boundary の欠陥は blocking とする。それ以外（発生条件が限定的な残余リスク、non-goal に属する影響、品質改善）は non-blocking とする。迷う場合は blocking に倒す。

## 処置のルール（architect / designer 側）

- **blocking 反例**は、次のどちらかが成立するまで設計を確定できない: (1) 設計を修正し、**同じ falsifier が修正後の設計で反例が閉じたことを再確認**する (2) 人間の判断で要件・リスク許容を明示的に変更する（対話中は構造化質問、自走中は高リスク未検証前提プロトコルの停止分岐）。architect / designer 単独の「受容 + 理由」で blocking を閉じることはできない。
- **non-blocking 反例**は architect / designer が処置（設計修正済み / 受容 + 理由）を決めてよい。
- すべての処置を設計の `### 反証` セクションへ、反例の blocking / non-blocking 区分とともに記録する。
