#!/usr/bin/env bash
# SessionStart hook: strip prose preambles out of the active registry.
#
# `index.md` is data, not a report (REGISTRY.md § Registries are data, not reports), so
# everything between its title and the first `## ` section heading is removed. Project
# rows are never touched, and a blockquote in that preamble — a hub's own pinned pointer,
# one line or several — is preserved whole, as one blockquote. Writes a .pre-preamble.bak
# before changing anything and is a no-op on a registry that is already clean.
#
# archive.md keeps its preamble by design: the rules for what may live there are stated
# nowhere else.
set -euo pipefail

HUB="${TODO_HUB:-$HOME/todo}"
case "$HUB" in "~"*) HUB="${HOME}${HUB#\~}" ;; esac

file_mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null || printf '644\n'
}

# Count real project rows, skipping the column header and the |---|---| separator.
project_rows() {
  grep -E '^\|' "$1" 2>/dev/null \
    | grep -Ev '^\| *short-name' \
    | grep -Ev '^\|[ :|-]+\|?[ ]*$' \
    | wc -l | tr -d ' '
}

strip_preamble() {
  local registry="$1"
  [ -f "$registry" ] || return 0
  # Only operate on a real registry — one with a section table header.
  grep -qE '^\|[^|]*short-name' "$registry" || return 0
  # A registry with no section heading is not a shape we understand; leave it alone.
  grep -qE '^## ' "$registry" || return 0

  local temp_file
  temp_file="$(mktemp)"
  local seen_title=0 in_preamble=0 stripped=0 in_quote=0

  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_preamble" -eq 1 ]; then
      case "$line" in
        '## '*)
          # Close a pinned blockquote that runs right up to the first section.
          [ "$in_quote" -eq 1 ] && printf '\n' >> "$temp_file"
          in_quote=0
          in_preamble=0
          ;;
        '>'*)
          # A hub's own pinned pointer. Keep every line of it together, so a multi-line
          # quote stays one blockquote; the blank line after it is written when it ends.
          printf '%s\n' "$line" >> "$temp_file"
          in_quote=1
          continue
          ;;
        *[![:space:]]*)
          if [ "$in_quote" -eq 1 ]; then
            # A lazy continuation line still belongs to the blockquote above it.
            printf '%s\n' "$line" >> "$temp_file"
            continue
          fi
          # Prose and link paragraphs are dropped.
          stripped=1
          continue
          ;;
        *)
          # A blank line ends a pinned blockquote; the separator is written once here.
          [ "$in_quote" -eq 1 ] && printf '\n' >> "$temp_file"
          in_quote=0
          [ -n "$line" ] && stripped=1
          continue
          ;;
      esac
    fi

    if [ "$seen_title" -eq 0 ] && [[ "$line" == '# '* ]]; then
      seen_title=1
      in_preamble=1
      printf '%s\n\n' "$line" >> "$temp_file"
      continue
    fi

    printf '%s\n' "$line" >> "$temp_file"
  done < "$registry"

  if [ "$stripped" -eq 0 ]; then
    rm -f "$temp_file"
    return 0
  fi

  # Never let a migration lose rows. Compare project-row counts and abort if they moved.
  local rows_before rows_after
  rows_before="$(project_rows "$registry")"
  rows_after="$(project_rows "$temp_file")"
  if [ "$rows_before" != "$rows_after" ]; then
    rm -f "$temp_file"
    printf 'todo-list: skipped the %s preamble migration — row count would change (%s to %s).\n' \
      "$registry" "$rows_before" "$rows_after"
    return 0
  fi

  chmod "$(file_mode "$registry")" "$temp_file"
  cp "$registry" "$registry.pre-preamble.bak"
  mv "$temp_file" "$registry"
  printf 'todo-list: removed the prose preamble from %s (%s rows kept). Backup at %s.pre-preamble.bak.\n' \
    "$registry" "$rows_after" "$registry"
}

strip_preamble "$HUB/index.md"
