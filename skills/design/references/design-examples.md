# design-contract 記入例

`design-contract.md` の各セクションの記入例。必要時のみ参照する。例は架空の取引システム（config で初期資金を持ち、DB に口座残高を保存し、reconciler が保護処理を回す）を題材にする。

## 事実と仮定

事実表:

| 値・挙動 | 正本の所在 | 確認方法 |
|---|---|---|
| 初期資金の config 値 = 100,000 | config | `config/trading.yaml` L12 |
| 口座残高の保存値は 1,000,000 起点の履歴 | DB 保存値 | `SELECT initial_cash FROM account` 相当の既存テスト fixture |
| runtime は起動時に config 値を読む | runtime 値 | `AccountBootstrap.kt` の起動経路 |

→ config 値と DB 保存値が不一致であることが確認済みの事実。「どちらかへ寄せる」判断は設計の決定事項として帰属付きで書く。

仮定表:

| 仮定 | 検証状態 | 間違っていた場合の影響 | リスク |
|---|---|---|---|
| 保存値 1,000,000 が運用実態 | 未検証 | 初期資金を誤った側へ揃え、全評価指標が崩れる | high |
| 表示 UI は runtime 値だけを参照 | 検証済み（`AccountView.kt`） | 表示のみの不整合 | low |

→ high / 未検証が残っているので、このままでは設計を確定できない（高リスク未検証前提プロトコルへ）。

## スコープ判定

> 網羅可能。跨る layer は domain と DB schema の 2 つ、不可逆 migration なし、security boundary 変更なし、consumer は API 1 つ、DB hot path 変更なし。

分割が必要な場合:

> 網羅不能。layer 5（DB schema / domain / API / UI / 権限）、不可逆 migration あり、consumer 4。次の 3 stage に分割する:
> - stage 1: schema 追加と非破壊 import（単独 merge/deploy 可、旧コードは新カラムを無視するため backward-compatible）
> - stage 2: domain write path と API（stage 1 に依存）
> - stage 3: UI と権限（stage 2 に依存）
>
> stage mapping: 受け入れ条件 1・2 → stage 1 / 条件 3・4 → stage 2 / 条件 5 → stage 3 / 「実資金対応」→ non-goal。

## 反証

> - ベクトル 3 の反例: `fetchStats()` を fail-closed 化すると、呼び出し元 `ReconcilerWorker.runPass()` が例外を warn で握って pass 全体を skip し、保護処理が停止する（`ReconcilerWorker.kt` の catch 節）→ 処置: 例外を failure transition へ伝播し、保護処理は継続する設計に修正済み。
> - ベクトル 4 の反例: baseline 不一致中の全 write 拒否は、STOP/TP・手動 close という risk-reducing write まで塞ぐ → 処置: 拒否は entry（risk-increasing）に限定し、exit 系は監査付きで許可する設計に修正済み。
> - ベクトル 1・2・5: 探索した結果反例なし。

## 状態遷移 matrix（抜粋）

| 状態 \ 操作 | entry（risk-increasing） | STOP/TP 決済（risk-reducing） | 手動 close（risk-reducing） |
|---|---|---|---|
| normal | 許可 | 許可 | 許可 |
| mismatch | 拒否（409 + 監査） | **許可**（監査 lineage 付き） | **許可**（監査付き） |
| degraded | 拒否 | 許可 | 許可 |

→ mismatch 行で risk-reducing 列が「拒否」になる設計は safety direction 違反。

## non-functional contract（抜粋）

| 項目 | 値 | 分類 |
|---|---|---|
| 1 決済あたりの insert 数 | 2（execution + 監査） | 既知（`LedgerWriter.kt`） |
| 監査 event の日次増加 | 約 17,000 行（5 秒周期 × 1 endpoint） | 推定（周期と endpoint 数から） |
| 監査 insert の p99 latency | — | 未測定。測定方法: deploy 後に DB の insert メトリクスを 1 週間観測。fail-safe 上限: 同期 insert が 100ms を超えたら周期を落とす。 |
