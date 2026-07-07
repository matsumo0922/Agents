#!/usr/bin/env sh
set -eu

ACTION="${1:-link}"
TARGETS="${TARGETS:-claude codex}"
REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SKILLS_ROOT="$REPO_ROOT/skills"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/.agents-repo-backups}"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"

usage() {
  cat <<'EOF'
Usage:
  scripts/link-skills.sh link
  scripts/link-skills.sh unlink
  scripts/link-skills.sh status

Environment:
  TARGETS="claude codex"   Target agents. Supported values: claude, codex.
  BACKUP_ROOT=PATH         Backup directory for existing entries.
EOF
}

target_dir() {
  agent_name="$1"

  case "$agent_name" in
    claude)
      printf '%s\n' "$HOME/.claude/skills"
      ;;
    codex)
      printf '%s\n' "$HOME/.codex/skills"
      ;;
    *)
      printf 'Unsupported target: %s\n' "$agent_name" >&2
      exit 1
      ;;
  esac
}

backup_existing_entry() {
  agent_name="$1"
  skill_name="$2"
  destination_path="$3"

  backup_path="$BACKUP_ROOT/$TIMESTAMP/$agent_name/$skill_name"
  mkdir -p "$(dirname -- "$backup_path")"
  mv "$destination_path" "$backup_path"
  printf 'backup %s -> %s\n' "$destination_path" "$backup_path"
}

link_skill() {
  agent_name="$1"
  skill_path="$2"
  skill_name="$(basename -- "$skill_path")"
  destination_dir="$(target_dir "$agent_name")"
  destination_path="$destination_dir/$skill_name"

  mkdir -p "$destination_dir"

  if [ -L "$destination_path" ]; then
    current_target="$(readlink "$destination_path")"

    if [ "$current_target" = "$skill_path" ]; then
      printf 'ok %s/%s -> %s\n' "$agent_name" "$skill_name" "$skill_path"
      return
    fi

    backup_existing_entry "$agent_name" "$skill_name" "$destination_path"
  elif [ -e "$destination_path" ]; then
    backup_existing_entry "$agent_name" "$skill_name" "$destination_path"
  fi

  ln -s "$skill_path" "$destination_path"
  printf 'linked %s/%s -> %s\n' "$agent_name" "$skill_name" "$skill_path"
}

unlink_skill() {
  agent_name="$1"
  skill_path="$2"
  skill_name="$(basename -- "$skill_path")"
  destination_path="$(target_dir "$agent_name")/$skill_name"

  if [ ! -L "$destination_path" ]; then
    printf 'skip %s/%s: not a symlink\n' "$agent_name" "$skill_name"
    return
  fi

  current_target="$(readlink "$destination_path")"

  if [ "$current_target" != "$skill_path" ]; then
    printf 'skip %s/%s: points to %s\n' "$agent_name" "$skill_name" "$current_target"
    return
  fi

  rm "$destination_path"
  printf 'unlinked %s/%s\n' "$agent_name" "$skill_name"
}

status_skill() {
  agent_name="$1"
  skill_path="$2"
  skill_name="$(basename -- "$skill_path")"
  destination_path="$(target_dir "$agent_name")/$skill_name"

  if [ -L "$destination_path" ]; then
    current_target="$(readlink "$destination_path")"

    if [ "$current_target" = "$skill_path" ]; then
      printf 'linked %s/%s -> %s\n' "$agent_name" "$skill_name" "$current_target"
    else
      printf 'different %s/%s -> %s\n' "$agent_name" "$skill_name" "$current_target"
    fi
  elif [ -e "$destination_path" ]; then
    printf 'existing %s/%s: real entry at %s\n' "$agent_name" "$skill_name" "$destination_path"
  else
    printf 'missing %s/%s\n' "$agent_name" "$skill_name"
  fi
}

run_for_skill() {
  agent_name="$1"
  skill_path="$2"

  case "$ACTION" in
    link)
      link_skill "$agent_name" "$skill_path"
      ;;
    unlink)
      unlink_skill "$agent_name" "$skill_path"
      ;;
    status)
      status_skill "$agent_name" "$skill_path"
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

if [ ! -d "$SKILLS_ROOT" ]; then
  printf 'No skills directory: %s\n' "$SKILLS_ROOT" >&2
  exit 1
fi

for skill_path in "$SKILLS_ROOT"/*; do
  [ -d "$skill_path" ] || continue
  [ -f "$skill_path/SKILL.md" ] || continue

  for agent_name in $TARGETS; do
    run_for_skill "$agent_name" "$skill_path"
  done
done
