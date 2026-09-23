#!/usr/bin/env bash
# todo-style: back up the global agent instruction file into the hub, then swap in the
# bundled briefing style pack — or put back what was there before it.
#
#   bash <todo-style-skill-dir>/scripts/agent-style.sh status
#   bash <todo-style-skill-dir>/scripts/agent-style.sh diff    [claude|codex|both]
#   bash <todo-style-skill-dir>/scripts/agent-style.sh install [claude|codex|both]
#   bash <todo-style-skill-dir>/scripts/agent-style.sh restore [claude|codex|both] [backup]
#   bash <todo-style-skill-dir>/scripts/agent-style.sh backups
#
# `uninstall` is another name for `restore`; `list-backups` is another name for `backups`.
#
# Invariants this script enforces, so the calling skill never has to:
#   1. An existing target file is copied into the hub and the copy is byte-verified
#      BEFORE the target is touched. A failed backup aborts without writing.
#   2. Backups are only ever added — never deleted, edited, or duplicated. Content that
#      already has a byte-identical backup is not copied again.
#   3. Installing an already-current file is a no-op — no redundant backup.
#   4. Install records a restore point: the backup of the user's own file, or `absent`
#      when there was no file. Installing over an earlier todo-list pack keeps the earlier
#      restore point, so restore always returns to the state before any pack.
#   5. `restore` returns to that restore point, so a second run is a no-op. It backs the
#      current file up first, unless that file is the untouched shipped pack, which the
#      plugin can hand back at any time. Returning to `absent` removes the file only
#      after that same backup.
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
assets_dir="$skill_dir/assets"
versions_file="$skill_dir/pack-versions.tsv"

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

other_agent() {
  case "$1" in
    claude) printf 'codex\n' ;;
    codex)  printf 'claude\n' ;;
  esac
}

backup_stem_for() {
  case "$1" in
    claude) printf 'claude-CLAUDE\n' ;;
    codex)  printf 'codex-AGENTS\n' ;;
  esac
}

restore_point_file() {
  printf '%s/%s.restore-point\n' "$backup_dir" "$(backup_stem_for "$1")"
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

# --- pack recognition ------------------------------------------------------

# sha256 of a file, or nothing when no hashing tool exists; recognition then falls back
# to byte-comparing against the two packs this copy of the plugin ships.
hash_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum < "$1" | cut -c1-64
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 < "$1" | cut -c1-64
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 < "$1" | awk '{ print $NF }'
  fi
}

# known_pack <file> — print "<pack> <version>" when the file is byte-identical to a
# todo-list style pack that has shipped, per pack-versions.tsv.
known_pack() {
  local sum
  [ -f "$1" ] && [ -f "$versions_file" ] || return 0
  sum="$(hash_of "$1")"
  [ -n "$sum" ] || return 0
  awk -F '\t' -v sum="$sum" '$1 == sum { print $2 " " $3; exit }' "$versions_file"
}

# is_pack <file> — true when the file is any todo-list pack, current or historical.
is_pack() {
  same_file "$1" "$(source_for claude)" && return 0
  same_file "$1" "$(source_for codex)" && return 0
  [ -n "$(known_pack "$1")" ]
}

# pack_shaped <file> — true for any todo-list pack, including one edited by hand: every
# shipped version carries both of these headings.
pack_shaped() {
  is_pack "$1" && return 0
  grep -qx '## AUDIENCE' "$1" && grep -qx '## BEHAVIOR' "$1"
}

# shipped_version <agent> — the pack version this copy of the plugin would install.
shipped_version() {
  local known
  known="$(known_pack "$(source_for "$1")")"
  if [ -n "$known" ] && [ "${known%% *}" = "$1" ]; then
    printf 'v%s\n' "${known#* }"
  else
    printf 'an unreleased pack (not in pack-versions.tsv)\n'
  fi
}

plugin_version() {
  local manifest
  for manifest in "$skill_dir/../../.claude-plugin/plugin.json" \
                  "$skill_dir/../../.codex-plugin/plugin.json"; do
    [ -f "$manifest" ] || continue
    awk -F '"' '/"version"[[:space:]]*:/ { print $4; exit }' "$manifest"
    return 0
  done
}

# describe_target <agent> — one phrase naming what the live file holds.
describe_target() {
  local agent="$1" target other known pack version
  target="$(target_for "$agent")"
  other="$(other_agent "$agent")"
  if [ ! -f "$target" ]; then
    printf 'absent (nothing to back up)\n'
  elif same_file "$target" "$(source_for "$agent")"; then
    printf 'current (already the shipped style pack, %s)\n' "$(shipped_version "$agent")"
  elif same_file "$target" "$(source_for "$other")"; then
    printf 'holds the %s pack (%s), not the %s one — install replaces it\n' \
      "$(label_for "$other")" "$(shipped_version "$other")" "$(label_for "$agent")"
  else
    known="$(known_pack "$target")"
    if [ -n "$known" ]; then
      pack="${known%% *}"
      version="${known#* }"
      if [ "$pack" = "$agent" ]; then
        printf 'an older todo-list pack (v%s) — install updates it\n' "$version"
      else
        printf 'holds an older %s pack (v%s), not the %s one — install replaces it\n' \
          "$(label_for "$pack")" "$version" "$(label_for "$agent")"
      fi
    elif pack_shaped "$target"; then
      printf 'a todo-list pack edited by hand (matches no shipped version)\n'
    else
      printf 'your own file (not a todo-list pack)\n'
    fi
  fi
}

# --- backup ----------------------------------------------------------------

seed_backup_dir() {
  mkdir -p "$backup_dir"
  [ -f "$backup_dir/README.md" ] && return 0
  cat > "$backup_dir/README.md" <<'EOF'
# Agent instruction backups

Every `.md` file here is a copy of a global agent instruction file (`~/.claude/CLAUDE.md`
or `~/.codex/AGENTS.md`) taken by `/todo-style` immediately before it overwrote or removed
that file. Backups are never deleted or rewritten, and the same content is never saved
twice.

Filenames are `<agent>-<file>-<UTC timestamp>-<run>.md`, one fixed shape, so the newest
backup for an agent sorts last.

`<agent>-<file>.restore-point` names what `/todo-style restore` puts back: the backup of
your own file taken at install, or `absent` when there was no file, in which case restore
removes the pack. Installing a newer pack over an older one keeps the restore point, and
restoring when the file already matches it changes nothing. Restore saves whatever it
replaces here first — unless that is the untouched style pack, which the plugin can always
hand back. So every backup in this folder is your own content.
EOF
}

# existing_backup <agent> <file> — print a backup already byte-identical to <file>.
existing_backup() {
  local stem candidate
  stem="$(backup_stem_for "$1")"
  [ -d "$backup_dir" ] || return 0
  for candidate in "$backup_dir"/"$stem"-*.md; do
    [ -e "$candidate" ] || continue
    if same_file "$candidate" "$2"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
}

# backup_target <agent> — make sure the live file is saved in the hub, echo the backup path.
backup_target() {
  local agent="$1" target stem stamp path suffix
  target="$(target_for "$agent")"
  stem="$(backup_stem_for "$agent")"
  [ -f "$target" ] || return 0

  path="$(existing_backup "$agent" "$target")"
  if [ -n "$path" ]; then
    printf '%s\n' "$path"
    return 0
  fi

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

# --- restore point ---------------------------------------------------------

# record_restore_point <agent> <backup-path|absent>
record_restore_point() {
  local file value="$2"
  file="$(restore_point_file "$1")"
  seed_backup_dir
  [ "$value" = absent ] || value="$(basename "$value")"
  printf '%s\n' "$value" > "$file.tmp.$$"
  mv "$file.tmp.$$" "$file"
}

# restore_point <agent> — print what restore returns to: a backup path, or `absent`.
# Installs made before restore points existed have no record, so infer one: the newest
# backup that is not a todo-list pack, edited or not; failing that, `absent` when the live
# file is absent or a pack, because install always backed an existing file up first.
# Prints nothing when neither applies.
restore_point() {
  local agent="$1" file value stem candidate newest='' target
  file="$(restore_point_file "$agent")"
  if [ -f "$file" ]; then
    value="$(head -n 1 "$file")"
    case "$value" in
      absent) printf 'absent\n' ;;
      ''|*/*) die "unreadable restore point in $file — name a backup: restore $agent <backup>" ;;
      *) printf '%s/%s\n' "$backup_dir" "$value" ;;
    esac
    return 0
  fi

  stem="$(backup_stem_for "$agent")"
  if [ -d "$backup_dir" ]; then
    for candidate in "$backup_dir"/"$stem"-*.md; do
      [ -e "$candidate" ] || continue
      pack_shaped "$candidate" || newest="$candidate"
    done
  fi
  if [ -n "$newest" ]; then
    printf '%s\n' "$newest"
    return 0
  fi
  target="$(target_for "$agent")"
  if [ ! -f "$target" ] || pack_shaped "$target"; then
    printf 'absent\n'
  fi
}

describe_restore_point() {
  local agent="$1" point note=''
  point="$(restore_point "$agent")"
  [ -f "$(restore_point_file "$agent")" ] || note=' (inferred; no install record)'
  case "$point" in
    '')     printf 'none\n' ;;
    absent) printf 'no file — restore removes the pack%s\n' "$note" ;;
    *)      printf '%s%s\n' "$point" "$note" ;;
  esac
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

# --- modes -----------------------------------------------------------------

mode_status() {
  local agent target backup state point plugin
  plugin="$(plugin_version)"
  printf 'hub: %s\n' "$hub"
  printf 'backups: %s\n' "$backup_dir"
  printf 'compared against: %s%s\n' "$assets_dir" "${plugin:+ (plugin $plugin)}"
  for agent in claude codex; do
    target="$(target_for "$agent")"
    state="$(describe_target "$agent")"
    point="$(describe_restore_point "$agent")"
    backup="$(newest_backup "$agent")"
    printf '\n%s\n' "$(label_for "$agent")"
    printf '  target:        %s\n' "$target"
    printf '  state:         %s\n' "$state"
    printf '  compared with: %s (%s)\n' "$(source_for "$agent")" "$(shipped_version "$agent")"
    printf '  restore point: %s\n' "$point"
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
  local agent source target backup point agents
  agents="$(resolve_agents "${1:-both}")"
  for agent in $agents; do
    source="$(source_for "$agent")"
    target="$(target_for "$agent")"
    [ -f "$source" ] || die "the bundled style pack is missing at $source"

    if same_file "$target" "$source"; then
      printf '%s: already current, no change (%s)\n' "$(label_for "$agent")" "$target"
      continue
    fi

    # Decide the restore point before anything is written.
    if [ ! -f "$target" ]; then
      point=absent
    elif is_pack "$target"; then
      # Swapping one todo-list pack for another: the state before any pack is still
      # what restore should return to.
      point="$(restore_point "$agent")"
    else
      point=''
    fi

    backup="$(backup_target "$agent")"
    [ -n "$point" ] || point="$backup"
    mkdir -p "$(dirname "$target")"
    cp "$source" "$target"
    same_file "$target" "$source" || die "the write to $target did not land"
    record_restore_point "$agent" "$point"

    if [ -n "$backup" ]; then
      printf '%s: installed to %s (previous file backed up to %s)\n' \
        "$(label_for "$agent")" "$target" "$backup"
    else
      printf '%s: installed to %s (no previous file existed; restore removes it again)\n' \
        "$(label_for "$agent")" "$target"
    fi
  done
}

mode_restore() {
  local requested="${1:-both}" explicit="${2:-}"
  local agent target point current agents

  if [ -n "$explicit" ] && [ "$requested" = "both" ]; then
    die "restoring a named backup needs one agent: restore claude|codex <backup>"
  fi

  agents="$(resolve_agents "$requested")"
  for agent in $agents; do
    target="$(target_for "$agent")"
    if [ -n "$explicit" ]; then
      point="$explicit"
      [ -f "$point" ] || die "no such backup: $point"
    else
      point="$(restore_point "$agent")"
      if [ -z "$point" ]; then
        printf '%s: no backup or install record in %s, nothing to restore\n' \
          "$(label_for "$agent")" "$backup_dir"
        continue
      fi
      [ "$point" = absent ] || [ -f "$point" ] ||
        die "the restore point $point is missing — name a backup: restore $agent <backup>"
    fi

    # Already there: change nothing and back nothing up, so restore never toggles.
    if [ "$point" = absent ] && [ ! -e "$target" ]; then
      printf '%s: no file at %s, as before the style pack — no change\n' \
        "$(label_for "$agent")" "$target"
      continue
    fi
    if [ "$point" != absent ] && same_file "$target" "$point"; then
      printf '%s: already matches %s, no change\n' "$(label_for "$agent")" "$point"
      continue
    fi

    # Back up whatever is there now — unless it is the untouched shipped pack, which the
    # plugin can hand back at any time. Skipping that keeps the backup folder made only of
    # the user's own content.
    if same_file "$target" "$(source_for "$agent")"; then
      current=''
    else
      current="$(backup_target "$agent")"
    fi

    if [ "$point" = absent ]; then
      rm -f "$target"
      [ ! -e "$target" ] || die "could not remove $target"
      printf '%s: removed %s — there was no file before the style pack%s\n' \
        "$(label_for "$agent")" "$target" "${current:+ (it was backed up to $current)}"
    else
      mkdir -p "$(dirname "$target")"
      cp "$point" "$target"
      same_file "$target" "$point" || die "the restore to $target did not land"
      if [ -n "$current" ]; then
        printf '%s: restored %s to %s (replaced file backed up to %s)\n' \
          "$(label_for "$agent")" "$point" "$target" "$current"
      else
        printf '%s: restored %s to %s\n' "$(label_for "$agent")" "$point" "$target"
      fi
    fi

    # Pin an inferred restore point, so the next restore is a no-op rather than a guess.
    if [ -z "$explicit" ] && [ ! -f "$(restore_point_file "$agent")" ]; then
      record_restore_point "$agent" "$point"
    fi
  done
}

mode_backups() {
  if [ ! -d "$backup_dir" ]; then
    printf 'no backups yet (%s does not exist)\n' "$backup_dir"
    return 0
  fi
  local found=0 agent file point
  for agent in claude codex; do
    point=''
    [ -f "$(restore_point_file "$agent")" ] && point="$(restore_point "$agent")"
    for file in "$backup_dir"/"$(backup_stem_for "$agent")"-*.md; do
      [ -e "$file" ] || continue
      found=1
      if [ "$file" = "$point" ]; then
        printf '%s  (restore point)\n' "$file"
      else
        printf '%s\n' "$file"
      fi
    done
  done
  [ "$found" -eq 1 ] || printf 'no backups yet in %s\n' "$backup_dir"
}

case "${1:-status}" in
  status)                mode_status ;;
  diff)                  mode_diff "${2:-both}" ;;
  install)               mode_install "${2:-both}" ;;
  restore|uninstall)     mode_restore "${2:-both}" "${3:-}" ;;
  backups|list-backups)  mode_backups ;;
  *) die "unknown mode '$1' — use status, diff, install, restore (or uninstall), or backups" ;;
esac
