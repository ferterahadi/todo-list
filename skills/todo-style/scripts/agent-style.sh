#!/usr/bin/env bash
# todo-style: back up the global agent instruction file into the hub, then swap in the
# bundled briefing style pack — or put the backup back.
#
#   bash <todo-style-skill-dir>/scripts/agent-style.sh status
#   bash <todo-style-skill-dir>/scripts/agent-style.sh diff    [claude|codex|both]
#   bash <todo-style-skill-dir>/scripts/agent-style.sh install [claude|codex|both]
#   bash <todo-style-skill-dir>/scripts/agent-style.sh restore [claude|codex|both] [backup]
#   bash <todo-style-skill-dir>/scripts/agent-style.sh list-backups
#
# Invariants this script enforces, so the calling skill never has to:
#   1. An existing target file is copied into the hub and the copy is byte-verified
#      BEFORE the target is touched. A failed backup aborts without writing.
#   2. Nothing is ever deleted. Every backup is kept, newest last by filename.
#   3. Installing an already-current file is a no-op — no redundant backup.
#   4. `restore` backs the current file up first, unless that file is the untouched
#      shipped pack, which the plugin can hand back at any time.
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
assets_dir="$skill_dir/assets"

die() {
  printf 'todo-style: %s\n' "$1" >&2
  exit 1
}

# Hub root, expanding a leading ~ the way the bootstrap hook does.
hub="${TODO_HUB:-$HOME/todo}"
case "$hub" in "~"*) hub="${HOME}${hub#\~}" ;; esac
backup_dir="$hub/backups/agent-instructions"

# --- per-agent facts -------------------------------------------------------

source_for() {
  case "$1" in
    claude) printf '%s\n' "$assets_dir/CLAUDE.md" ;;
    codex)  printf '%s\n' "$assets_dir/AGENTS.md" ;;
  esac
}

target_for() {
  case "$1" in
    claude) printf '%s/CLAUDE.md\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ;;
    codex)  printf '%s/AGENTS.md\n'  "${CODEX_HOME:-$HOME/.codex}" ;;
  esac
}

label_for() {
  case "$1" in
    claude) printf 'Claude Code\n' ;;
    codex)  printf 'Codex\n' ;;
  esac
}

backup_stem_for() {
  case "$1" in
    claude) printf 'claude-CLAUDE\n' ;;
    codex)  printf 'codex-AGENTS\n' ;;
  esac
}

resolve_agents() {
  case "${1:-both}" in
    claude) printf 'claude\n' ;;
    codex)  printf 'codex\n' ;;
    both|all|"") printf 'claude\ncodex\n' ;;
    *) die "unknown agent '$1' — use claude, codex, or both" ;;
  esac
}

same_file() {
  # cmp exits 1 on difference; keep that off `set -e`.
  [ -f "$1" ] && [ -f "$2" ] && cmp -s "$1" "$2"
}

newest_backup() {
  local stem file newest=''
  stem="$(backup_stem_for "$1")"
  [ -d "$backup_dir" ] || return 0
  # Every name is `<stem>-<UTC stamp>-<nn>.md`, one fixed shape, so the last glob match
  # is the newest backup.
  for file in "$backup_dir"/"$stem"-*.md; do
    [ -e "$file" ] || continue
    newest="$file"
  done
  [ -z "$newest" ] || printf '%s\n' "$newest"
}

# --- backup ----------------------------------------------------------------

seed_backup_dir() {
  mkdir -p "$backup_dir"
  [ -f "$backup_dir/README.md" ] && return 0
  cat > "$backup_dir/README.md" <<'EOF'
# Agent instruction backups

Every file here is a copy of a global agent instruction file (`~/.claude/CLAUDE.md` or
`~/.codex/AGENTS.md`) taken by `/todo-style` immediately before it overwrote that file.
Nothing here is ever deleted or rewritten.

Filenames are `<agent>-<file>-<UTC timestamp>-<run>.md`, one fixed shape, so the newest
backup for an agent sorts last. `/todo-style restore` puts that one back, saving whatever
it replaces here first — unless what it replaces is the untouched style pack, which the
plugin can always hand back. So every file in this folder is your own content.
EOF
}

# backup_target <agent> — copy the live file into the hub, echo the backup path.
backup_target() {
  local agent="$1" target stem stamp path suffix
  target="$(target_for "$agent")"
  stem="$(backup_stem_for "$agent")"
  [ -f "$target" ] || return 0

  seed_backup_dir
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  # Fixed-width run counter: two backups in the same second still sort in order.
  suffix=1
  path="$(printf '%s/%s-%s-%02d.md' "$backup_dir" "$stem" "$stamp" "$suffix")"
  while [ -e "$path" ]; do
    suffix=$((suffix + 1))
    path="$(printf '%s/%s-%s-%02d.md' "$backup_dir" "$stem" "$stamp" "$suffix")"
  done

  cp "$target" "$path" || die "could not write the backup at $path — nothing was changed"
  same_file "$target" "$path" ||
    die "the backup at $path does not match $target — nothing was changed"
  printf '%s\n' "$path"
}

# --- modes -----------------------------------------------------------------

mode_status() {
  printf 'hub: %s\n' "$hub"
  printf 'backups: %s\n' "$backup_dir"
  local agent source target backup state
  for agent in claude codex; do
    source="$(source_for "$agent")"
    target="$(target_for "$agent")"
    if [ ! -f "$target" ]; then
      state='absent (nothing to back up)'
    elif same_file "$target" "$source"; then
      state='current (already the shipped style pack)'
    else
      state='differs from the shipped style pack'
    fi
    backup="$(newest_backup "$agent")"
    printf '\n%s\n' "$(label_for "$agent")"
    printf '  target: %s\n' "$target"
    printf '  state:  %s\n' "$state"
    printf '  newest backup: %s\n' "${backup:-none}"
  done
}

mode_diff() {
  local agent source target status agents
  # Resolve first, as its own assignment: a bad agent name must abort the run, and a
  # failure inside `for x in $(...)` would be swallowed.
  agents="$(resolve_agents "${1:-both}")"
  for agent in $agents; do
    source="$(source_for "$agent")"
    target="$(target_for "$agent")"
    printf '=== %s: %s\n' "$(label_for "$agent")" "$target"
    if [ ! -f "$target" ]; then
      printf 'no current file — install would create it\n\n'
      continue
    fi
    status=0
    diff -u --label "current: $target" --label "shipped: $source" \
      "$target" "$source" || status=$?
    [ "$status" -le 1 ] || die "diff failed for $target"
    [ "$status" -eq 0 ] && printf 'identical — nothing would change\n'
    printf '\n'
  done
}

mode_install() {
  local agent source target backup agents
  agents="$(resolve_agents "${1:-both}")"
  for agent in $agents; do
    source="$(source_for "$agent")"
    target="$(target_for "$agent")"
    [ -f "$source" ] || die "the bundled style pack is missing at $source"

    if same_file "$target" "$source"; then
      printf '%s: already current, no change (%s)\n' "$(label_for "$agent")" "$target"
      continue
    fi

    backup="$(backup_target "$agent")"
    mkdir -p "$(dirname "$target")"
    cp "$source" "$target"
    same_file "$target" "$source" || die "the write to $target did not land"

    if [ -n "$backup" ]; then
      printf '%s: installed to %s (previous file backed up to %s)\n' \
        "$(label_for "$agent")" "$target" "$backup"
    else
      printf '%s: installed to %s (no previous file existed)\n' \
        "$(label_for "$agent")" "$target"
    fi
  done
}

mode_restore() {
  local requested="${1:-both}" explicit="${2:-}"
  local agent target backup current agents

  if [ -n "$explicit" ] && [ "$requested" = "both" ]; then
    die "restoring a named backup needs one agent: restore claude|codex <backup>"
  fi

  agents="$(resolve_agents "$requested")"
  for agent in $agents; do
    target="$(target_for "$agent")"
    if [ -n "$explicit" ]; then
      backup="$explicit"
      [ -f "$backup" ] || die "no such backup: $backup"
    else
      backup="$(newest_backup "$agent")"
      [ -n "$backup" ] || {
        printf '%s: no backup in %s, nothing to restore\n' \
          "$(label_for "$agent")" "$backup_dir"
        continue
      }
    fi

    if same_file "$target" "$backup"; then
      printf '%s: already matches %s, no change\n' "$(label_for "$agent")" "$backup"
      continue
    fi

    # Back up whatever is there now — unless it is the untouched shipped pack, which the
    # plugin can hand back at any time. Skipping that keeps the backup folder made only of
    # the user's own content, and keeps `restore` idempotent instead of toggling.
    if same_file "$target" "$(source_for "$agent")"; then
      current=''
    else
      current="$(backup_target "$agent")"
    fi
    mkdir -p "$(dirname "$target")"
    cp "$backup" "$target"
    same_file "$target" "$backup" || die "the restore to $target did not land"

    if [ -n "$current" ]; then
      printf '%s: restored %s to %s (replaced file backed up to %s)\n' \
        "$(label_for "$agent")" "$backup" "$target" "$current"
    else
      printf '%s: restored %s to %s\n' "$(label_for "$agent")" "$backup" "$target"
    fi
  done
}

mode_list_backups() {
  if [ ! -d "$backup_dir" ]; then
    printf 'no backups yet (%s does not exist)\n' "$backup_dir"
    return 0
  fi
  local found=0 file
  for file in "$backup_dir"/claude-CLAUDE-*.md "$backup_dir"/codex-AGENTS-*.md; do
    [ -e "$file" ] || continue
    found=1
    printf '%s\n' "$file"
  done
  [ "$found" -eq 1 ] || printf 'no backups yet in %s\n' "$backup_dir"
}

case "${1:-status}" in
  status)        mode_status ;;
  diff)          mode_diff "${2:-both}" ;;
  install)       mode_install "${2:-both}" ;;
  restore)       mode_restore "${2:-both}" "${3:-}" ;;
  list-backups)  mode_list_backups ;;
  *) die "unknown mode '$1' — use status, diff, install, restore, or list-backups" ;;
esac
