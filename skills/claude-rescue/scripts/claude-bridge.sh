#!/usr/bin/env sh
set -u

# claude-bridge.sh: Claude を headless (claude -p) で呼び出し、構造化された結果を返すブリッジ。
#
# Usage:
#   claude-bridge.sh <instruction-file> [--model <model>] [--effort <level>] \
#                    [--resume <session-id>] [--expect <tag>] [--allowed-tools <list>]
#
# 出力契約:
#   stdout = result 本文
#   stderr = session_id / cost_usd / duration_ms のメタ情報(KEY=value)
# exit code 契約:
#   0 = 成功
#   2 = 形式違反(1 回の自動リトライ後も --expect タグブロック不成立。result は stdout に出力済み)
#   3 = 不通(引数不正・claude コマンド失敗・応答の契約違反・permission denial・is_error)

MODEL="claude-opus-4-8"
EFFORT="high"
RESUME=""
EXPECT=""
# Bash を素通しで allow する。危険コマンド(rm -rf / sudo / git config / 秘密ファイル
# 読取 等)は settings.json の deny が全モードで最優先に効くため、そちらで弾く。
# Edit / Write は allow しないので、正規の編集ツール経由でのファイル改変は起きない。
ALLOWED_TOOLS="Read,Grep,Glob,Bash"

usage() {
  sed -n '4,16p' "$0" | sed 's/^# \{0,1\}//'
}

if [ $# -lt 1 ]; then
  usage >&2
  exit 3
fi

case "$1" in
  help|-h|--help)
    usage
    exit 0
    ;;
esac

INSTRUCTION_FILE="$1"
shift

require_value() {
  option_name="$1"
  remaining="$2"

  if [ "$remaining" -lt 2 ]; then
    printf 'claude-bridge: option %s requires a value\n' "$option_name" >&2
    exit 3
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --model)
      require_value "$1" $#; MODEL="$2"; shift 2 ;;
    --effort)
      require_value "$1" $#; EFFORT="$2"; shift 2 ;;
    --resume)
      require_value "$1" $#; RESUME="$2"; shift 2 ;;
    --expect)
      require_value "$1" $#; EXPECT="$2"; shift 2 ;;
    --allowed-tools)
      require_value "$1" $#; ALLOWED_TOOLS="$2"; shift 2 ;;
    *)
      printf 'claude-bridge: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 3
      ;;
  esac
done

if [ ! -f "$INSTRUCTION_FILE" ]; then
  printf 'claude-bridge: instruction file not found: %s\n' "$INSTRUCTION_FILE" >&2
  exit 3
fi

if ! command -v claude >/dev/null 2>&1; then
  printf 'claude-bridge: claude command not found\n' >&2
  exit 3
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/claude-bridge.XXXXXX")" || exit 3
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM HUP

# 応答 JSON を一括検証し、result 本文とメタ情報をファイルへ書き出す。
# 契約: type == "result" / is_error == false (bool) / permission_denials が空の list /
#       result が文字列 / session_id 非空 / cost・duration が数値。
# 違反時は理由を stderr に出して非ゼロで返る。
validate_response() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys

json_path, result_path, meta_path = sys.argv[1:4]

def fail(msg):
    print("claude-bridge: " + msg, file=sys.stderr)
    sys.exit(1)

try:
    with open(json_path) as f:
        d = json.load(f)
except Exception:
    fail("response is not valid JSON")

if not isinstance(d, dict) or d.get("type") != "result":
    fail("response type is not 'result'")

is_error = d.get("is_error")
if is_error:
    status = d.get("api_error_status")
    if status is not None:
        print(f"api_error_status={status}", file=sys.stderr)
    body = d.get("result")
    if isinstance(body, str) and body:
        print(body, file=sys.stderr)
    fail("is_error is truthy")
if is_error is not False:
    fail("is_error is not false")

denials = d.get("permission_denials")
if not isinstance(denials, list):
    fail("permission_denials is not a list")
if denials:
    fail("permission_denials is not empty: "
         + json.dumps(denials, ensure_ascii=False)[:2000])

result = d.get("result")
if not isinstance(result, str):
    fail("result is not a string")

session_id = d.get("session_id")
if not isinstance(session_id, str) or not session_id:
    fail("session_id is missing")

cost = d.get("total_cost_usd")
duration = d.get("duration_ms")
if isinstance(cost, bool) or not isinstance(cost, (int, float)):
    fail("total_cost_usd is not a number")
if isinstance(duration, bool) or not isinstance(duration, (int, float)):
    fail("duration_ms is not a number")

with open(result_path, "w") as f:
    f.write(result)
with open(meta_path, "w") as f:
    f.write(f"session_id={session_id}\ncost_usd={cost}\nduration_ms={duration}\n")
PY
}

# claude -p を 1 回実行する。$1 = prompt file, $2 = resume session id (空可), $3 = 出力 JSON の保存先
run_claude() {
  prompt_file="$1"
  resume_id="$2"
  out_file="$3"

  set -- -p --model "$MODEL" --effort "$EFFORT" --output-format json \
    --permission-mode dontAsk --allowedTools "$ALLOWED_TOOLS"
  if [ -n "$resume_id" ]; then
    set -- "$@" --resume "$resume_id"
  fi

  claude "$@" <"$prompt_file" >"$out_file" 2>"$TMP_DIR/claude-stderr"
}

# 実行 + 応答検証。不通なら診断を stderr に出して exit 3
attempt() {
  prompt_file="$1"
  resume_id="$2"
  out_file="$3"
  result_file="$4"
  meta_file="$5"

  run_claude "$prompt_file" "$resume_id" "$out_file"
  rc=$?

  if [ $rc -ne 0 ]; then
    printf 'claude-bridge: claude exited with %d\n' "$rc" >&2
    cat "$TMP_DIR/claude-stderr" >&2
    # JSON が返っていれば api_error_status 等の診断を出す
    validate_response "$out_file" /dev/null /dev/null || true
    exit 3
  fi

  if ! validate_response "$out_file" "$result_file" "$meta_file"; then
    exit 3
  fi
}

meta_field() {
  grep "^$2=" "$1" | head -1 | cut -d= -f2-
}

# result 内に <tag>...</tag> のブロック(開始タグ → 終了タグの順)があるか検査する
has_expect_block() {
  python3 - "$1" "$EXPECT" <<'PY'
import re, sys
with open(sys.argv[1]) as f:
    text = f.read()
tag = re.escape(sys.argv[2])
sys.exit(0 if re.search(rf"<{tag}>[\s\S]*?</{tag}>", text) else 1)
PY
}

emit_meta() {
  printf 'session_id=%s\n' "$SESSION_ID" >&2
  printf 'cost_usd=%s\n' "$TOTAL_COST" >&2
  printf 'duration_ms=%s\n' "$TOTAL_DURATION" >&2
}

attempt "$INSTRUCTION_FILE" "$RESUME" "$TMP_DIR/response-1.json" "$TMP_DIR/result" "$TMP_DIR/meta-1"

SESSION_ID="$(meta_field "$TMP_DIR/meta-1" session_id)"
TOTAL_COST="$(meta_field "$TMP_DIR/meta-1" cost_usd)"
TOTAL_DURATION="$(meta_field "$TMP_DIR/meta-1" duration_ms)"

if [ -z "$EXPECT" ] || has_expect_block "$TMP_DIR/result"; then
  cat "$TMP_DIR/result"
  emit_meta
  exit 0
fi

# --expect ブロック欠落: 同一セッションで「指定形式のみで再送」を 1 回だけ自動再依頼する
printf 'claude-bridge: expect block <%s> missing, retrying once\n' "$EXPECT" >&2

cat >"$TMP_DIR/retry-prompt" <<EOF
直前の応答に <$EXPECT>...</$EXPECT> ブロック(開始タグ → 終了タグの順)が含まれていない。同じ内容を <$EXPECT>...</$EXPECT> ブロックで囲んで再送せよ。ブロックの外には何も書くな。
EOF

attempt "$TMP_DIR/retry-prompt" "$SESSION_ID" "$TMP_DIR/response-2.json" "$TMP_DIR/result" "$TMP_DIR/meta-2"

SESSION_ID="$(meta_field "$TMP_DIR/meta-2" session_id)"
TOTAL_COST="$(python3 -c "print(round($TOTAL_COST + $(meta_field "$TMP_DIR/meta-2" cost_usd), 6))")"
TOTAL_DURATION="$(python3 -c "print(int($TOTAL_DURATION + $(meta_field "$TMP_DIR/meta-2" duration_ms)))")"

cat "$TMP_DIR/result"
emit_meta

if has_expect_block "$TMP_DIR/result"; then
  exit 0
fi

printf 'claude-bridge: expect block <%s> still missing after retry\n' "$EXPECT" >&2
exit 2
