---
name: claude-rescue
description: "Claude を headless(claude -p)で呼び出し、構造化された結果を受け取る汎用ブリッジ。diff レビュー・設計反証・任意成果物の検証のセカンドオピニオンに使う。Use when the user asks to get a second opinion from Claude, claude にレビューさせて, claude に反証させて, headless で claude を呼んで, or when an agent without Claude subagents (e.g. Codex) needs to invoke Claude as a reviewer or falsifier."
---

# Claude Rescue

任意の環境から Claude を headless(`claude -p`)で呼び出し、構造化された結果を受け取る汎用ブリッジ。エントリポイントは `scripts/claude-bridge.sh` の 1 つだけで、レビュー・反証・検証など依頼内容は instruction ファイルが決める。

本 skill が提供するのは呼び出しの機構のみ。どのモデルをどの役割に使うか、失敗時にどう切り替えるかは利用側が決める。

## 位置づけ

- 主な利用元は Claude サブエージェントを持たない環境(Codex 等)。そこから Claude をレビュアー・反証者・セカンドオピニオンとして呼び出す
- Claude Code 環境の通常会話では Agent tool が上位互換(コンテキスト共有・並列実行・進捗追跡)。Claude Code 内で本 skill を使うのは、exit code 契約や `--expect` の機械検査が必要な scripted flow に限られる
- 呼び出しごとに Claude の usage を消費する

## 使い方

```bash
scripts/claude-bridge.sh <instruction-file> [--model <model>] [--effort <level>] \
                         [--resume <session-id>] [--expect <tag>] [--allowed-tools <list>]
```

- instruction はファイル渡し(長文指示の shell quoting を回避する)
- 既定値: `--model claude-opus-4-8` / `--effort high` / `--allowed-tools "Read,Grep,Glob"`(読み取りのみ)。既定は安全側の値であり、すべて引数で上書きできる
- `--expect <tag>`: result に `<tag>...</tag>` ブロック(開始タグ → 終了タグの順)が含まれることを機械検査する。欠落時は同一セッションへ「指定形式のみで再送」を 1 回だけ自動再依頼する
- `--resume <session-id>`: 既存セッションを継続する(レビュー round 2 の追記など)。session_id は前回呼び出しの stderr から取得する

### 出力契約

- stdout = result 本文
- stderr = メタ情報(`session_id=` / `cost_usd=` / `duration_ms=` の KEY=value 行と診断メッセージ)
- exit code: `0` = 成功 / `2` = 形式違反(リトライ後も `--expect` タグブロック不成立。result は stdout に出力済み) / `3` = 不通(引数不正・claude コマンド失敗・応答の契約違反・permission denial・`is_error`)。利用側は exit code だけで分岐できる
- 応答は一括検証される: `type == "result"`・`is_error == false`・`permission_denials` が空・result / session_id / cost / duration の型。**permission denial は exit 3**(必要なファイルを読めなかった不完全な結果を成功として採用しないため)

### 例: diff レビューを依頼して round 2 で追記する

レビュー対象の diff は呼び出し側が事前にファイルへ書き出し、instruction から参照させる(Claude に Bash を渡さないため)。作業ファイルは cwd 配下の一時ディレクトリに置き、終了時に削除して worktree を汚さない。

```bash
work_dir="$(mktemp -d ./claude-rescue-work.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT

git diff main...HEAD > "$work_dir/review-target.diff"

cat > "$work_dir/review-instruction.md" <<EOF
$work_dir/review-target.diff の diff をレビューし、must-fix / should / nits に分類して
<review_result>...</review_result> ブロックで報告せよ。
EOF

scripts/claude-bridge.sh "$work_dir/review-instruction.md" --expect review_result 2>"$work_dir/meta.txt"
session_id="$(grep '^session_id=' "$work_dir/meta.txt" | cut -d= -f2)"

git diff main...HEAD > "$work_dir/review-target.diff"

cat > "$work_dir/round2.md" <<EOF
指摘 M-1 と M-2 を修正した(commit abc1234)。$work_dir/review-target.diff を再レビューし、同じ形式で報告せよ。
EOF

scripts/claude-bridge.sh "$work_dir/round2.md" --resume "$session_id" --expect review_result
```

## 環境知識

- **Codex から呼ぶ場合は `require_escalated` で起動する**。session の保存と `--resume` による round 追記には `~/.claude/projects` への書き込みが必要で、通常 sandbox では失敗する。auto-approve 環境では escalation は無人で承認される。単発呼び出し(`--resume` を使わない)だけなら通常 sandbox でも動く
- `claude` バイナリと `~/.claude` の認証情報、api.anthropic.com への到達性が必要
- **`Bash(git diff*)` 型の prefix 許可は read-only 境界にならない**。prefix は複合コマンド(`git diff; 任意のコマンド`)にもマッチするため、非信頼入力(PR diff 等)を読ませる用途では prompt injection の実行経路になる。既定の allowed-tools に Bash を含めないのはこのためで、diff 等は呼び出し側がファイルへ書き出して渡す
- headless の Claude は作業ディレクトリ外(例: `/tmp`)へのアクセスを拒否することがある。instruction が参照するファイルは呼び出し時の cwd 配下に置く
- 存在しないモデル・認証失敗は `is_error` / HTTP status として返り、bridge が exit 3 に変換する
- 出力形式の軽微な逸脱(タグ欠落)は起き得る。機械処理する場合は instruction に出力契約を書いた上で `--expect` を併用する
