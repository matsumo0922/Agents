# fukurou-llm-daemon-log-audit

fukurou production の LLM daemon / paper trading runtime を read-only で確認し、`llm_runs`、`command_event_log`、`decisions`、paper ledger を時系列表へ復元するためのスキルです。

## 使う場面

- LLM daemon を有効化した後の挙動を報告する。
- `NO_TRADE_DECISION` / `NO_TRADE_AUDITED` / fail-closed の意味を説明する。
- 前回確認した run 以降を、翌日以降も同じ表形式で追跡する。
- paper trading が発注・約定に進んだかを確認する。

## 主な手順

1. `scripts/prod-curl` で revision、readiness、evaluation API を確認する。
2. `scripts/query-fukurou-llm-daemon-log.sh --since "YYYY-MM-DD HH:MM:SS+09"` で production DB を read-only 集計する。
3. `RUN` 行を時系列表へ変換し、`SKIP` 行と paper ledger を別枠で報告する。

DB credential は container 内の環境変数だけを使い、値を出力しません。
