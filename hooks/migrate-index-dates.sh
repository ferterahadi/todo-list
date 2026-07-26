#!/usr/bin/env bash
# SessionStart hook: migrate active and archived registries to the nine-column format.
set -euo pipefail

HUB="${TODO_HUB:-$HOME/todo}"
case "$HUB" in "~"*) HUB="${HOME}${HUB#\~}" ;; esac

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

HAS_GIT=0
if git -C "$HUB" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  HAS_GIT=1
fi

first_commit_date() { git -C "$HUB" log --reverse --format=%as -- "$1" 2>/dev/null | head -1; }
last_commit_date() { git -C "$HUB" log -1 --format=%as -- "$1" 2>/dev/null; }

to_epoch() {
  date -d "$1" +%s 2>/dev/null || date -j -f '%Y-%m-%d' "$1" +%s 2>/dev/null || true
}

elapsed_days() {
  local started_epoch completed_epoch
  started_epoch="$(to_epoch "$1")"
  completed_epoch="$(to_epoch "$2")"
  if [ -n "$started_epoch" ] && [ -n "$completed_epoch" ] && [ "$completed_epoch" -ge "$started_epoch" ]; then
    echo $(( (completed_epoch - started_epoch) / 86400 ))
  else
    echo "-"
  fi
}

file_mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null || printf '644\n'
}

migrate_registry() {
  local registry="$1"
  [ -f "$registry" ] || return 0
  grep -qE '^\|[^|]*short-name' "$registry" || return 0
  if ! grep -E '^\|[^|]*short-name' "$registry" | grep -qv 'started'; then
    return 0
  fi

  local temp_file
  temp_file="$(mktemp)"
  local migrated=0
  local in_old_table=0

  while IFS= read -r line || [ -n "$line" ]; do
    case "$in_old_table" in
      1)
        echo '|---|---|---|---|---|---|---|---|---|' >> "$temp_file"
        in_old_table=2
        continue
        ;;
      2)
        if [[ "$line" != \|* ]]; then
          in_old_table=0
        else
          local c_name c_path c_repo c_status c_info c_related
          IFS='|' read -r _ c_name c_path c_repo c_status c_info c_related _ <<< "$line"
          local name path repo status status_lower info related path_plain
          name="$(trim "$c_name")"
          path="$(trim "$c_path")"
          repo="$(trim "$c_repo")"
          status="$(trim "$c_status")"
          status_lower="$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')"
          info="$(trim "$c_info")"
          related="$(trim "$c_related")"
          path_plain="${path//\`/}"

          local started="-" completed="-" elapsed="-"
          if [ "$HAS_GIT" -eq 1 ] && [ -n "$path_plain" ] && [ "$path_plain" != "-" ]; then
            local date_value
            date_value="$(first_commit_date "$path_plain")"
            [ -n "$date_value" ] && started="$date_value"
            if [ "$status_lower" = done ]; then
              date_value="$(last_commit_date "$path_plain")"
              [ -n "$date_value" ] && completed="$date_value"
              [ "$started" = "-" ] && started="$completed"
              if [ "$started" != "-" ] && [ "$completed" != "-" ]; then
                elapsed="$(elapsed_days "$started" "$completed")"
              fi
            fi
          fi

          printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
            "$name" "$path" "$repo" "$status" "$started" "$completed" "$elapsed" "$info" "$related" \
            >> "$temp_file"
          continue
        fi
        ;;
    esac

    if [[ "$line" == \|* ]] && [[ "$line" == *short-name* ]] && [[ "$line" != *started* ]]; then
      echo '| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |' >> "$temp_file"
      in_old_table=1
      migrated=1
      continue
    fi

    echo "$line" >> "$temp_file"
  done < "$registry"

  if [ "$migrated" -eq 0 ]; then
    rm -f "$temp_file"
    return 0
  fi

  chmod "$(file_mode "$registry")" "$temp_file"
  cp "$registry" "$registry.pre-dates.bak"
  mv "$temp_file" "$registry"
  local source_note
  if [ "$HAS_GIT" -eq 1 ]; then
    source_note="backfilled from the hub's git history"
  else
    source_note="left as '-' (hub is not a git repo)"
  fi
  printf 'todo-list: migrated %s to the dated table format (%s). Backup at %s.pre-dates.bak.\n' \
    "$registry" "$source_note" "$registry"
}

migrate_registry "$HUB/index.md"
migrate_registry "$HUB/archive.md"
