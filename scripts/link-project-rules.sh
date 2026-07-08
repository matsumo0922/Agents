#!/usr/bin/env sh
set -eu

ACTION="${1:-help}"
if [ $# -ge 1 ]; then
  shift
fi

REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
KOTLIN_RULES="$REPO_ROOT/rules/kotlin.md"
LINT_DETEKT="$REPO_ROOT/rules/lint/detekt.yml"
LINT_EDITORCONFIG="$REPO_ROOT/rules/lint/.editorconfig"
BEGIN_MARKER='<!-- agents-rules:kotlin:begin -->'
END_MARKER='<!-- agents-rules:kotlin:end -->'
NOTE_LINE='<!-- この区間は Agents リポジトリが管理する。編集は Agents の rules/kotlin.md で行い、make link-project で更新する -->'

usage() {
  cat <<'EOF'
Usage:
  scripts/link-project-rules.sh link PROJECT_DIR...
  scripts/link-project-rules.sh unlink PROJECT_DIR...
  scripts/link-project-rules.sh status PROJECT_DIR...

link:
  - PROJECT_DIR/AGENTS.md に rules/kotlin.md を管理ブロックとして注入・更新する
  - PROJECT_DIR/CLAUDE.md が無ければ `@AGENTS.md` の1行で作成する
  - rules/lint/ の detekt.yml / .editorconfig を、存在しない場合のみコピーする
unlink:
  - AGENTS.md の管理ブロックだけを削除する（CLAUDE.md と lint ファイルは残す）
status:
  - 管理ブロック・CLAUDE.md・lint ファイルの状態を表示する（読み取り専用）
EOF
}

case "$ACTION" in
  link|unlink|status)
    ;;
  help|-h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

if [ $# -eq 0 ]; then
  printf 'No project directory given\n' >&2
  usage >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

expected_block() {
  printf '%s\n' "$BEGIN_MARKER"
  printf '%s\n' "$NOTE_LINE"
  cat "$KOTLIN_RULES"
  printf '%s\n' "$END_MARKER"
}

has_block() {
  grep -qF "$BEGIN_MARKER" "$1" 2>/dev/null
}

current_block() {
  awk -v begin_marker="$BEGIN_MARKER" -v end_marker="$END_MARKER" '
    $0 == begin_marker { inside = 1 }
    inside { print }
    $0 == end_marker { inside = 0 }
  ' "$1"
}

remove_block() {
  awk -v begin_marker="$BEGIN_MARKER" -v end_marker="$END_MARKER" '
    $0 == begin_marker { inside = 1; next }
    $0 == end_marker { inside = 0; next }
    !inside { print }
  ' "$1"
}

link_agents_md() {
  project_dir="$1"
  agents_path="$project_dir/AGENTS.md"

  expected_block > "$TMP_DIR/expected.md"

  if [ ! -f "$agents_path" ]; then
    cat "$TMP_DIR/expected.md" > "$agents_path"
    printf 'created %s\n' "$agents_path"
    return
  fi

  if has_block "$agents_path"; then
    current_block "$agents_path" > "$TMP_DIR/current.md"

    if cmp -s "$TMP_DIR/current.md" "$TMP_DIR/expected.md"; then
      printf 'ok %s\n' "$agents_path"
      return
    fi

    remove_block "$agents_path" > "$TMP_DIR/rest.md"
    { cat "$TMP_DIR/rest.md"; cat "$TMP_DIR/expected.md"; } > "$TMP_DIR/merged.md"
    cat "$TMP_DIR/merged.md" > "$agents_path"
    printf 'updated %s\n' "$agents_path"
    return
  fi

  { printf '\n'; cat "$TMP_DIR/expected.md"; } >> "$agents_path"
  printf 'appended %s\n' "$agents_path"
}

link_claude_md() {
  project_dir="$1"
  claude_path="$project_dir/CLAUDE.md"

  if [ ! -e "$claude_path" ] && [ ! -L "$claude_path" ]; then
    printf '@AGENTS.md\n' > "$claude_path"
    printf 'created %s\n' "$claude_path"
    return
  fi

  if grep -qF '@AGENTS.md' "$claude_path" 2>/dev/null; then
    printf 'ok %s\n' "$claude_path"
  else
    printf 'warn %s: @AGENTS.md への参照がない\n' "$claude_path"
  fi
}

copy_lint_file() {
  source_path="$1"
  destination_path="$2"

  if [ -e "$destination_path" ]; then
    if cmp -s "$source_path" "$destination_path"; then
      printf 'ok %s\n' "$destination_path"
    else
      printf 'skip %s: customized\n' "$destination_path"
    fi
    return
  fi

  mkdir -p "$(dirname -- "$destination_path")"
  cp "$source_path" "$destination_path"
  printf 'copied %s\n' "$destination_path"
}

unlink_agents_md() {
  project_dir="$1"
  agents_path="$project_dir/AGENTS.md"

  if [ ! -f "$agents_path" ] || ! has_block "$agents_path"; then
    printf 'skip %s: no managed block\n' "$agents_path"
    return
  fi

  remove_block "$agents_path" > "$TMP_DIR/rest.md"
  cat "$TMP_DIR/rest.md" > "$agents_path"
  printf 'removed block %s\n' "$agents_path"
}

status_agents_md() {
  project_dir="$1"
  agents_path="$project_dir/AGENTS.md"

  if [ ! -f "$agents_path" ]; then
    printf 'missing %s\n' "$agents_path"
    return
  fi

  if ! has_block "$agents_path"; then
    printf 'no block %s\n' "$agents_path"
    return
  fi

  expected_block > "$TMP_DIR/expected.md"
  current_block "$agents_path" > "$TMP_DIR/current.md"

  if cmp -s "$TMP_DIR/current.md" "$TMP_DIR/expected.md"; then
    printf 'linked %s\n' "$agents_path"
  else
    printf 'stale %s: rules/kotlin.md と差分あり\n' "$agents_path"
  fi
}

status_claude_md() {
  project_dir="$1"
  claude_path="$project_dir/CLAUDE.md"

  if [ ! -e "$claude_path" ]; then
    printf 'missing %s\n' "$claude_path"
  elif grep -qF '@AGENTS.md' "$claude_path" 2>/dev/null; then
    printf 'ok %s\n' "$claude_path"
  else
    printf 'warn %s: @AGENTS.md への参照がない\n' "$claude_path"
  fi
}

status_lint_file() {
  source_path="$1"
  destination_path="$2"

  if [ ! -e "$destination_path" ]; then
    printf 'missing %s\n' "$destination_path"
  elif cmp -s "$source_path" "$destination_path"; then
    printf 'ok %s\n' "$destination_path"
  else
    printf 'customized %s\n' "$destination_path"
  fi
}

run_for_project() {
  project_dir="$1"

  if [ ! -d "$project_dir" ]; then
    printf 'Not a directory: %s\n' "$project_dir" >&2
    exit 1
  fi

  case "$ACTION" in
    link)
      link_agents_md "$project_dir"
      link_claude_md "$project_dir"
      copy_lint_file "$LINT_DETEKT" "$project_dir/config/detekt/detekt.yml"
      copy_lint_file "$LINT_EDITORCONFIG" "$project_dir/.editorconfig"
      ;;
    unlink)
      unlink_agents_md "$project_dir"
      ;;
    status)
      status_agents_md "$project_dir"
      status_claude_md "$project_dir"
      status_lint_file "$LINT_DETEKT" "$project_dir/config/detekt/detekt.yml"
      status_lint_file "$LINT_EDITORCONFIG" "$project_dir/.editorconfig"
      ;;
  esac
}

if [ ! -f "$KOTLIN_RULES" ]; then
  printf 'No kotlin rules file: %s\n' "$KOTLIN_RULES" >&2
  exit 1
fi

for project_dir in "$@"; do
  run_for_project "$project_dir"
done
