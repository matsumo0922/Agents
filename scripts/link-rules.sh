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

backup_existing_entry() {
  agent_name="$1"
  rule_name="$2"
  destination_path="$3"

  backup_path="$BACKUP_ROOT/$TIMESTAMP/$agent_name/$rule_name"
  mkdir -p "$(dirname -- "$backup_path")"
  mv "$destination_path" "$backup_path"
  printf 'backup %s -> %s\n' "$destination_path" "$backup_path"
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
    help|-h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

run_for_agent() {
  agent_name="$1"

  case "$agent_name" in
    claude)
      run_for_rule "$agent_name" "$RULES_ROOT/AGENTS.md" "$HOME/.claude/AGENTS.md"
      run_for_rule "$agent_name" "$RULES_ROOT/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
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
