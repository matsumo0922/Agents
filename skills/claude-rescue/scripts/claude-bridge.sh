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
#   2 = 形式違反(1 回の自動リトライ後も --expect タグ不成立。result は stdout に出力済み)
#   3 = 不通(claude コマンド失敗・JSON 解析不能・is_error)

MODEL="claude-opus-4-8"
EFFORT="high"
RESUME=""
EXPECT=""
ALLOWED_TOOLS="Read,Grep,Glob,Bash(git diff*),Bash(git log*),Bash(git rev-parse*)"

usage() {
  sed -n '4,17p' "$0" | sed 's/^# \{0,1\}//'
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

while [ $# -gt 0 ]; do
  case "$1" in
    --model)
      MODEL="$2"; shift 2 ;;
    --effort)
      EFFORT="$2"; shift 2 ;;
    --resume)
      RESUME="$2"; shift 2 ;;
    --expect)
      EXPECT="$2"; shift 2 ;;
    --allowed-tools)
      ALLOWED_TOOLS="$2"; shift 2 ;;
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

# JSON からフィールドを 1 つ取り出す(欠落は空文字、bool は true/false)
json_field() {
  python3 - "$1" "$2" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
except Exception:
    sys.exit(1)
v = d.get(sys.argv[2])
if v is None:
    print("")
elif isinstance(v, bool):
    print("true" if v else "false")
else:
    print(v)
PY
}

# result 本文をそのまま書き出す(改行を保存するためファイル経由)
json_result() {
  python3 - "$1" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
sys.stdout.write(d.get("result") or "")
PY
}

# claude -p を 1 回実行する。$1 = prompt file, $2 = resume session id (空可), $3 = 出力 JSON の保存先
run_claude() {
  prompt_file="$1"
  resume_id="$2"
  out_file="$3"

  set -- -p --model "$MODEL" --effort "$EFFORT" --output-format json --allowedTools "$ALLOWED_TOOLS"
  if [ -n "$resume_id" ]; then
    set -- "$@" --resume "$resume_id"
  fi

  claude "$@" <"$prompt_file" >"$out_file" 2>"$TMP_DIR/claude-stderr"
}

# 実行 + JSON 検証。不通なら診断を stderr に出して exit 3
attempt() {
  prompt_file="$1"
  resume_id="$2"
  out_file="$3"

  run_claude "$prompt_file" "$resume_id" "$out_file"
  rc=$?

  if [ $rc -ne 0 ]; then
    printf 'claude-bridge: claude exited with %d\n' "$rc" >&2
    cat "$TMP_DIR/claude-stderr" >&2
    api_status="$(json_field "$out_file" api_error_status 2>/dev/null || true)"
    [ -n "${api_status:-}" ] && printf 'api_error_status=%s\n' "$api_status" >&2
    exit 3
  fi

  if ! json_field "$out_file" is_error >"$TMP_DIR/is-error" 2>/dev/null; then
    printf 'claude-bridge: output is not valid JSON\n' >&2
    head -c 2000 "$out_file" >&2
    exit 3
  fi

  if [ "$(cat "$TMP_DIR/is-error")" = "true" ]; then
    printf 'claude-bridge: is_error=true\n' >&2
    api_status="$(json_field "$out_file" api_error_status)"
    [ -n "$api_status" ] && printf 'api_error_status=%s\n' "$api_status" >&2
    json_result "$out_file" >&2
    printf '\n' >&2
    exit 3
  fi
}

has_expect_tag() {
  result_file="$1"
  grep -qF "<$EXPECT>" "$result_file" && grep -qF "</$EXPECT>" "$result_file"
}

emit_meta() {
  printf 'session_id=%s\n' "$SESSION_ID" >&2
  printf 'cost_usd=%s\n' "$TOTAL_COST" >&2
  printf 'duration_ms=%s\n' "$TOTAL_DURATION" >&2
}

attempt "$INSTRUCTION_FILE" "$RESUME" "$TMP_DIR/response-1.json"

SESSION_ID="$(json_field "$TMP_DIR/response-1.json" session_id)"
TOTAL_COST="$(json_field "$TMP_DIR/response-1.json" total_cost_usd)"
TOTAL_DURATION="$(json_field "$TMP_DIR/response-1.json" duration_ms)"
json_result "$TMP_DIR/response-1.json" >"$TMP_DIR/result"

if [ -z "$EXPECT" ] || has_expect_tag "$TMP_DIR/result"; then
  cat "$TMP_DIR/result"
  emit_meta
  exit 0
fi

# --expect タグ欠落: 同一セッションで「指定形式のみで再送」を 1 回だけ自動再依頼する
printf 'claude-bridge: expect tag <%s> missing, retrying once\n' "$EXPECT" >&2

cat >"$TMP_DIR/retry-prompt" <<EOF
直前の応答に <$EXPECT>...</$EXPECT> ブロックが含まれていない。同じ内容を <$EXPECT>...</$EXPECT> ブロックで囲んで再送せよ。ブロックの外には何も書くな。
EOF

attempt "$TMP_DIR/retry-prompt" "$SESSION_ID" "$TMP_DIR/response-2.json"

SESSION_ID="$(json_field "$TMP_DIR/response-2.json" session_id)"
retry_cost="$(json_field "$TMP_DIR/response-2.json" total_cost_usd)"
retry_duration="$(json_field "$TMP_DIR/response-2.json" duration_ms)"
TOTAL_COST="$(python3 -c "print(round(float('${TOTAL_COST:-0}' or 0) + float('${retry_cost:-0}' or 0), 6))")"
TOTAL_DURATION="$(python3 -c "print(int(float('${TOTAL_DURATION:-0}' or 0) + float('${retry_duration:-0}' or 0)))")"
json_result "$TMP_DIR/response-2.json" >"$TMP_DIR/result"

cat "$TMP_DIR/result"
emit_meta

if has_expect_tag "$TMP_DIR/result"; then
  exit 0
fi

printf 'claude-bridge: expect tag <%s> still missing after retry\n' "$EXPECT" >&2
exit 2
