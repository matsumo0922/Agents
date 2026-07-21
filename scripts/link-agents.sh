#!/usr/bin/env sh
set -eu

ACTION="${1:-link}"
REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
AGENTS_ROOT="$REPO_ROOT/agents"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/.agents-repo-backups}"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"

usage() {
  cat <<'EOF'
Usage:
  scripts/link-agents.sh link
  scripts/link-agents.sh unlink
  scripts/link-agents.sh status

Environment:
  BACKUP_ROOT=PATH   Backup directory for existing entries.

Distributes agents/*.md to ~/.claude/agents/ (Claude Code only; Codex has no
agent definition concept).
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

target_dir() {
  printf '%s\n' "$HOME/.claude/agents"
}

backup_existing_entry() {
  agent_file_name="$1"
  destination_path="$2"

  backup_path="$BACKUP_ROOT/$TIMESTAMP/claude/$agent_file_name"
  mkdir -p "$(dirname -- "$backup_path")"
  mv "$destination_path" "$backup_path"
  printf 'backup %s -> %s\n' "$destination_path" "$backup_path"
}

link_agent() {
  agent_path="$1"
  agent_file_name="$(basename -- "$agent_path")"
  destination_dir="$(target_dir)"
  destination_path="$destination_dir/$agent_file_name"

  mkdir -p "$destination_dir"

  if [ -L "$destination_path" ]; then
    current_target="$(readlink "$destination_path")"

    if [ "$current_target" = "$agent_path" ]; then
      printf 'ok claude/%s -> %s\n' "$agent_file_name" "$agent_path"
      return
    fi

    backup_existing_entry "$agent_file_name" "$destination_path"
  elif [ -e "$destination_path" ]; then
    backup_existing_entry "$agent_file_name" "$destination_path"
  fi

  ln -s "$agent_path" "$destination_path"
  printf 'linked claude/%s -> %s\n' "$agent_file_name" "$agent_path"
}

unlink_agent() {
  agent_path="$1"
  agent_file_name="$(basename -- "$agent_path")"
  destination_path="$(target_dir)/$agent_file_name"

  if [ ! -L "$destination_path" ]; then
    printf 'skip claude/%s: not a symlink\n' "$agent_file_name"
    return
  fi

  current_target="$(readlink "$destination_path")"

  if [ "$current_target" != "$agent_path" ]; then
    printf 'skip claude/%s: points to %s\n' "$agent_file_name" "$current_target"
    return
  fi

  rm "$destination_path"
  printf 'unlinked claude/%s\n' "$agent_file_name"
}

status_agent() {
  agent_path="$1"
  agent_file_name="$(basename -- "$agent_path")"
  destination_path="$(target_dir)/$agent_file_name"

  if [ -L "$destination_path" ]; then
    current_target="$(readlink "$destination_path")"

    if [ "$current_target" = "$agent_path" ]; then
      printf 'linked claude/%s -> %s\n' "$agent_file_name" "$current_target"
    else
      printf 'different claude/%s -> %s\n' "$agent_file_name" "$current_target"
    fi
  elif [ -e "$destination_path" ]; then
    printf 'existing claude/%s: real entry at %s\n' "$agent_file_name" "$destination_path"
  else
    printf 'missing claude/%s\n' "$agent_file_name"
  fi
}

run_for_agent() {
  agent_path="$1"

  case "$ACTION" in
    link)
      link_agent "$agent_path"
      ;;
    unlink)
      unlink_agent "$agent_path"
      ;;
    status)
      status_agent "$agent_path"
      ;;
  esac
}

if [ ! -d "$AGENTS_ROOT" ]; then
  printf 'No agents directory: %s\n' "$AGENTS_ROOT" >&2
  exit 1
fi

for agent_path in "$AGENTS_ROOT"/*.md; do
  [ -f "$agent_path" ] || continue

  run_for_agent "$agent_path"
done
