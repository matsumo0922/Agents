# claude-rescue

任意の環境から Claude を headless(`claude -p`)で呼び出し、構造化された結果を受け取る汎用ブリッジのスキルです。diff レビュー・設計反証・任意成果物の検証など、Claude へのセカンドオピニオン依頼に使います。

## 使いどころ

- Claude サブエージェントを持たない環境(Codex 等)から、Claude をレビュアー・反証者として呼び出したいとき
- exit code だけで成否を分岐できる scripted flow に Claude の判断を組み込みたいとき
- 「claude にレビューさせて」「claude に反証させて」と依頼したいとき

## 設計の要点

- **機構のみを提供**: エントリポイントは `scripts/claude-bridge.sh` の 1 つだけ。依頼内容は instruction ファイルが決め、モデル選定やエスカレーションの政策は利用側が持つ
- **exit code 契約**: `0` = 成功 / `2` = 形式違反 / `3` = 不通。stdout = result 本文、stderr = メタ情報(session_id / cost_usd / duration_ms)で、利用側は JSON 解析なしで分岐できる
- **応答の一括検証**: `type`・`is_error`・`permission_denials`・必須フィールドの型を検査し、permission denial を含む不完全な応答は成功にしない(exit 3)
- **`--expect` による形式保証**: result に指定タグのブロック(開始タグ → 終了タグの順)が含まれることを機械検査し、欠落時は同一セッションへ 1 回だけ自動再依頼する
- **`--resume` によるセッション継続**: レビュー round 2 の追記など、同一文脈での往復に対応する

## インターフェース

```bash
scripts/claude-bridge.sh <instruction-file> [--model <model>] [--effort <level>] \
                         [--resume <session-id>] [--expect <tag>] [--allowed-tools <list>]
```

既定値は `--model claude-opus-4-8` / `--effort high` / `--allowed-tools "Read,Grep,Glob"`（読み取りのみ。Bash の prefix 許可は複合コマンドにもマッチして read-only 境界にならないため、既定に含めません）です。すべて引数で上書きできます。詳細な使い方と環境知識（Codex では `require_escalated` が必要、など）は [SKILL.md](SKILL.md) を参照してください。

## 依存

- `claude` CLI と `~/.claude` の認証情報
- `python3`(JSON 解析に使用)
