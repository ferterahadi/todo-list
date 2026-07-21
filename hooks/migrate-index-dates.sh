#!/usr/bin/env bash
# SessionStart hook (todo-list plugin): migrate index.md to the dated table format.
#
# Widens any pre-1.2 six-column section table (short-name|path|repo|status|infographic|related)
# to the nine-column format by inserting started / completed / elapsed (days) after status,
# then backfills the new cells from the hub's git history:
#   started   — date of the first commit touching the project's path
#   completed — date of the last commit touching the path (done projects only)
#   elapsed   — completed − started, whole days
# No git repo, or no commits for a path → the cell stays "-".
# Idempotent and SILENT once index.md is already in the new format.
set -euo pipefail

HUB="${TODO_HUB:-$HOME/todo}"
case "$HUB" in "~"*) HUB="${HOME}${HUB#\~}" ;; esac
INDEX="$HUB/index.md"

[ -f "$INDEX" ] || exit 0                          # no hub yet — bootstrap handles it
grep -qE '^\|[^|]*short-name' "$INDEX" || exit 0   # no project tables at all
# Already migrated? Every header row that has short-name also has started.
if ! grep -E '^\|[^|]*short-name' "$INDEX" | grep -qv 'started'; then exit 0; fi

# --- helpers -----------------------------------------------------------------

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

HAS_GIT=0
if git -C "$HUB" rev-parse --is-inside-work-tree >/dev/null 2>&1; then HAS_GIT=1; fi

# First / last commit date (YYYY-MM-DD) touching a path; empty if none.
first_commit_date() { git -C "$HUB" log --reverse --format=%as -- "$1" 2>/dev/null | head -1; }
last_commit_date()  { git -C "$HUB" log -1 --format=%as -- "$1" 2>/dev/null; }

# YYYY-MM-DD → epoch seconds, portable across GNU and BSD date. Empty on failure.
to_epoch() {
  date -d "$1" +%s 2>/dev/null || date -j -f '%Y-%m-%d' "$1" +%s 2>/dev/null || true
}

elapsed_days() { # $1=started $2=completed → whole days or "-"
  local s e
  s="$(to_epoch "$1")"; e="$(to_epoch "$2")"
  if [ -n "$s" ] && [ -n "$e" ] && [ "$e" -ge "$s" ]; then
    echo $(( (e - s) / 86400 ))
  else
    echo "-"
  fi
}

# --- rewrite -----------------------------------------------------------------

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
migrated=0
in_old_table=0   # 0=outside, 1=expect separator, 2=in rows

while IFS= read -r line || [ -n "$line" ]; do
  case "$in_old_table" in
    1)  # separator line of an old-format table
      echo '|---|---|---|---|---|---|---|---|---|' >>"$TMP"
      in_old_table=2
      continue
      ;;
    2)
      if [[ "$line" != \|* ]]; then
        in_old_table=0   # table ended; fall through to normal handling
      else
        # Old row: | short-name | path | repo | status | infographic | related |
        IFS='|' read -r _ c_name c_path c_repo c_status c_info c_related _ <<<"$line"
        name="$(trim "$c_name")"; path="$(trim "$c_path")"; repo="$(trim "$c_repo")"
        status="$(trim "$c_status")"; info="$(trim "$c_info")"; related="$(trim "$c_related")"
        path_plain="${path//\`/}"   # tolerate backticked cells

        started="-"; completed="-"; elapsed="-"
        if [ "$HAS_GIT" -eq 1 ] && [ -n "$path_plain" ] && [ "$path_plain" != "-" ]; then
          d="$(first_commit_date "$path_plain")"; [ -n "$d" ] && started="$d"
          if [ "$status" = "done" ]; then
            d="$(last_commit_date "$path_plain")"; [ -n "$d" ] && completed="$d"
            [ "$started" = "-" ] && started="$completed"
            if [ "$started" != "-" ] && [ "$completed" != "-" ]; then
              elapsed="$(elapsed_days "$started" "$completed")"
            fi
          fi
        fi
        printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
          "$name" "$path" "$repo" "$status" "$started" "$completed" "$elapsed" "$info" "$related" >>"$TMP"
        continue
      fi
      ;;
  esac

  # Old-format header (has short-name, lacks started) starts a table to migrate.
  if [[ "$line" == \|* ]] && [[ "$line" == *short-name* ]] && [[ "$line" != *started* ]]; then
    echo '| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |' >>"$TMP"
    in_old_table=1
    migrated=1
    continue
  fi

  echo "$line" >>"$TMP"
done <"$INDEX"

if [ "$migrated" -eq 1 ]; then
  cp "$INDEX" "$INDEX.pre-dates.bak"
  mv "$TMP" "$INDEX"
  trap - EXIT
  if [ "$HAS_GIT" -eq 1 ]; then
    src="backfilled from the hub's git history"
  else
    src="left as '-' (hub is not a git repo)"
  fi
  printf 'todo-list: migrated %s to the dated table format (started / completed / elapsed columns added; %s). Backup at index.md.pre-dates.bak.\n' "$INDEX" "$src"
fi
exit 0
