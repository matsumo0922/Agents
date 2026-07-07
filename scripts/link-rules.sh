#!/usr/bin/env sh
set -eu

ACTION="${1:-link}"
TARGETS="${TARGETS:-claude codex}"
REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
RULES_ROOT="$REPO_ROOT/rules"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/.agents-repo-backups}"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"

usage() {
  cat <<'EOF'
Usage:
  scripts/link-rules.sh link
  scripts/link-rules.sh unlink
  scripts/link-rules.sh status

Environment:
  TARGETS="claude codex"   Target agents. Supported values: claude, codex.
  BACKUP_ROOT=PATH         Backup directory for existing entries.
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

backup_existing_entry() {
  agent_name="$1"
  rule_name="$2"
  destination_path="$3"

  backup_path="$BACKUP_ROOT/$TIMESTAMP/$agent_name/$rule_name"
  mkdir -p "$(dirname -- "$backup_path")"
  mv "$destination_path" "$backup_path"
  printf 'backup %s -> %s\n' "$destination_path" "$backup_path"
}

claude_wrapper_content() {
  printf '@%s\n' "$RULES_ROOT/AGENTS.md"
  printf '@RTK.md\n'
}

is_expected_claude_wrapper() {
  destination_path="$1"

  if [ ! -f "$destination_path" ] || [ -L "$destination_path" ]; then
    return 1
  fi

  current_content="$(cat "$destination_path")"
  expected_content="$(claude_wrapper_content)"

  [ "$current_content" = "$expected_content" ]
}

link_claude_wrapper() {
  destination_path="$HOME/.claude/CLAUDE.md"

  if [ ! -f "$RULES_ROOT/AGENTS.md" ]; then
    printf 'missing source claude/CLAUDE.md: %s\n' "$RULES_ROOT/AGENTS.md" >&2
    exit 1
  fi

  mkdir -p "$(dirname -- "$destination_path")"

  if is_expected_claude_wrapper "$destination_path"; then
    printf 'ok claude/CLAUDE.md -> generated wrapper\n'
    return
  fi

  if [ -L "$destination_path" ] || [ -e "$destination_path" ]; then
    backup_existing_entry claude CLAUDE.md "$destination_path"
  fi

  claude_wrapper_content > "$destination_path"
  printf 'generated claude/CLAUDE.md -> %s\n' "$RULES_ROOT/AGENTS.md"
}

unlink_claude_wrapper() {
  destination_path="$HOME/.claude/CLAUDE.md"

  if is_expected_claude_wrapper "$destination_path"; then
    rm "$destination_path"
    printf 'unlinked claude/CLAUDE.md\n'
    return
  fi

  if [ -L "$destination_path" ]; then
    current_target="$(readlink "$destination_path")"

    if [ "$current_target" = "$RULES_ROOT/CLAUDE.md" ]; then
      rm "$destination_path"
      printf 'unlinked claude/CLAUDE.md\n'
      return
    fi

    printf 'skip claude/CLAUDE.md: points to %s\n' "$current_target"
    return
  fi

  if [ -e "$destination_path" ]; then
    printf 'skip claude/CLAUDE.md: real entry at %s\n' "$destination_path"
  else
    printf 'skip claude/CLAUDE.md: missing\n'
  fi
}

status_claude_wrapper() {
  destination_path="$HOME/.claude/CLAUDE.md"

  if is_expected_claude_wrapper "$destination_path"; then
    printf 'generated claude/CLAUDE.md -> %s\n' "$RULES_ROOT/AGENTS.md"
  elif [ -L "$destination_path" ]; then
    current_target="$(readlink "$destination_path")"
    printf 'different claude/CLAUDE.md -> %s\n' "$current_target"
  elif [ -e "$destination_path" ]; then
    printf 'existing claude/CLAUDE.md: real entry at %s\n' "$destination_path"
  else
    printf 'missing claude/CLAUDE.md\n'
  fi
}

status_claude_agents_placeholder() {
  destination_path="$HOME/.claude/AGENTS.md"

  if [ -L "$destination_path" ]; then
    current_target="$(readlink "$destination_path")"
    printf 'unmanaged claude/AGENTS.md -> %s\n' "$current_target"
  elif [ -e "$destination_path" ]; then
    printf 'unmanaged claude/AGENTS.md: real entry at %s\n' "$destination_path"
  else
    printf 'missing claude/AGENTS.md (not managed)\n'
  fi
}

cleanup_managed_claude_agents_link() {
  destination_path="$HOME/.claude/AGENTS.md"

  if [ ! -L "$destination_path" ]; then
    return
  fi

  current_target="$(readlink "$destination_path")"

  if [ "$current_target" = "$RULES_ROOT/AGENTS.md" ]; then
    rm "$destination_path"
    printf 'removed claude/AGENTS.md managed link\n'
  fi
}

link_rule() {
  agent_name="$1"
  source_path="$2"
  destination_path="$3"
  rule_name="$(basename -- "$destination_path")"

  if [ ! -f "$source_path" ]; then
    printf 'missing source %s/%s: %s\n' "$agent_name" "$rule_name" "$source_path" >&2
    exit 1
  fi

  mkdir -p "$(dirname -- "$destination_path")"

  if [ -L "$destination_path" ]; then
    current_target="$(readlink "$destination_path")"

    if [ "$current_target" = "$source_path" ]; then
      printf 'ok %s/%s -> %s\n' "$agent_name" "$rule_name" "$source_path"
      return
    fi

    backup_existing_entry "$agent_name" "$rule_name" "$destination_path"
  elif [ -e "$destination_path" ]; then
    backup_existing_entry "$agent_name" "$rule_name" "$destination_path"
  fi

  ln -s "$source_path" "$destination_path"
  printf 'linked %s/%s -> %s\n' "$agent_name" "$rule_name" "$source_path"
}

unlink_rule() {
  agent_name="$1"
  source_path="$2"
  destination_path="$3"
  rule_name="$(basename -- "$destination_path")"

  if [ ! -L "$destination_path" ]; then
    printf 'skip %s/%s: not a symlink\n' "$agent_name" "$rule_name"
    return
  fi

  current_target="$(readlink "$destination_path")"

  if [ "$current_target" != "$source_path" ]; then
    printf 'skip %s/%s: points to %s\n' "$agent_name" "$rule_name" "$current_target"
    return
  fi

  rm "$destination_path"
  printf 'unlinked %s/%s\n' "$agent_name" "$rule_name"
}

status_rule() {
  agent_name="$1"
  source_path="$2"
  destination_path="$3"
  rule_name="$(basename -- "$destination_path")"

  if [ -L "$destination_path" ]; then
    current_target="$(readlink "$destination_path")"

    if [ "$current_target" = "$source_path" ]; then
      printf 'linked %s/%s -> %s\n' "$agent_name" "$rule_name" "$current_target"
    else
      printf 'different %s/%s -> %s\n' "$agent_name" "$rule_name" "$current_target"
    fi
  elif [ -e "$destination_path" ]; then
    printf 'existing %s/%s: real entry at %s\n' "$agent_name" "$rule_name" "$destination_path"
  else
    printf 'missing %s/%s\n' "$agent_name" "$rule_name"
  fi
}

run_for_rule() {
  agent_name="$1"
  source_path="$2"
  destination_path="$3"

  case "$ACTION" in
    link)
      link_rule "$agent_name" "$source_path" "$destination_path"
      ;;
    unlink)
      unlink_rule "$agent_name" "$source_path" "$destination_path"
      ;;
    status)
      status_rule "$agent_name" "$source_path" "$destination_path"
      ;;
  esac
}

run_for_agent() {
  agent_name="$1"

  case "$agent_name" in
    claude)
      case "$ACTION" in
        link)
          cleanup_managed_claude_agents_link
          link_claude_wrapper
          ;;
        unlink)
          cleanup_managed_claude_agents_link
          unlink_claude_wrapper
          ;;
        status)
          status_claude_agents_placeholder
          status_claude_wrapper
          ;;
      esac
      ;;
    codex)
      run_for_rule "$agent_name" "$RULES_ROOT/AGENTS.md" "$HOME/.codex/AGENTS.md"
      ;;
    *)
      printf 'Unsupported target: %s\n' "$agent_name" >&2
      exit 1
      ;;
  esac
}

if [ ! -d "$RULES_ROOT" ]; then
  printf 'No rules directory: %s\n' "$RULES_ROOT" >&2
  exit 1
fi

for agent_name in $TARGETS; do
  run_for_agent "$agent_name"
done
