#!/usr/bin/env bash
# Read-only archive helper.
# - audit: compact candidate report for /todo-archive
# - hook: one-line SessionStart report, silent when clean
# - context: bounded current-task summary for /todo-refer
# - lookup: print one live or archived revision without ingesting unrelated history
set -euo pipefail

usage() {
  printf '%s\n' \
    'usage:' \
    '  archive-report.sh audit [hub-root] [short-name]' \
    '  archive-report.sh hook [hub-root]' \
    '  archive-report.sh context <hub-root> <project-path>' \
    '  archive-report.sh lookup <hub-root> <project-path> <revision-id>' >&2
  exit 2
}

expand_hub() {
  local value="$1"
  case "$value" in
    "~"*) value="${HOME}${value#\~}" ;;
  esac
  printf '%s\n' "$value"
}

revision_stats() {
  local tasks="$1"
  awk '
    function visible(value, start, rest, ending) {
      if (in_comment) {
        ending = index(value, "-->")
        if (!ending) return ""
        value = substr(value, ending + 3)
        in_comment = 0
      }
      while ((start = index(value, "<!--")) > 0) {
        rest = substr(value, start + 4)
        ending = index(rest, "-->")
        if (ending) {
          value = substr(value, 1, start - 1) substr(rest, ending + 3)
        } else {
          value = substr(value, 1, start - 1)
          in_comment = 1
          break
        }
      }
      return value
    }
    function finish_entry() {
      if (in_revision && is_done && has_detail && !has_pointer) detailed_done++
    }
    function reset_entry() {
      in_revision = 0
      is_done = 0
      has_detail = 0
      has_pointer = 0
    }

    {
      line = visible($0)
      if (line == "") next
      if (line ~ /^[[:space:]]*(```|~~~)/) {
        in_fence = !in_fence
        next
      }
      if (in_fence) next
    }

    line ~ /^## Revisions[[:space:]]*$/ {
      finish_entry()
      reset_entry()
      in_revisions = 1
      next
    }
    in_revisions && line ~ /^## / {
      finish_entry()
      reset_entry()
      in_revisions = 0
      next
    }
    !in_revisions { next }

    line ~ /^### [Rr][0-9]+[A-Za-z]*/ {
      finish_entry()
      in_revision = 1
      lower = tolower(line)
      is_done = lower ~ /\[done[^]]*\][[:space:]]*$/
      if (lower ~ /\[open[^]]*\][[:space:]]*$/) open_revisions++
      has_detail = 0
      has_pointer = 0
      next
    }

    in_revision && line ~ /^### / {
      finish_entry()
      reset_entry()
      next
    }

    in_revision && line ~ /^- archived →/ {
      has_pointer = 1
      next
    }
    in_revision && line ~ /[^[:space:]]/ {
      has_detail = 1
    }

    END {
      finish_entry()
      printf "%d\t%d\n", detailed_done + 0, open_revisions + 0
    }
  ' "$tasks"
}

pointer_records() {
  local tasks="$1"
  awk '
    function visible(value, start, rest, ending) {
      if (in_comment) {
        ending = index(value, "-->")
        if (!ending) return ""
        value = substr(value, ending + 3)
        in_comment = 0
      }
      while ((start = index(value, "<!--")) > 0) {
        rest = substr(value, start + 4)
        ending = index(rest, "-->")
        if (ending) {
          value = substr(value, 1, start - 1) substr(rest, ending + 3)
        } else {
          value = substr(value, 1, start - 1)
          in_comment = 1
          break
        }
      }
      return value
    }

    {
      line = visible($0)
      if (line == "") next
      if (line ~ /^[[:space:]]*(```|~~~)/) {
        in_fence = !in_fence
        next
      }
      if (in_fence) next
    }

    line ~ /^## Revisions[[:space:]]*$/ {
      in_revisions = 1
      revision_id = ""
      next
    }
    in_revisions && line ~ /^## / {
      in_revisions = 0
      revision_id = ""
      next
    }
    !in_revisions { next }

    line ~ /^### [Rr][0-9]+[A-Za-z]*/ {
      split(line, fields, /[[:space:]]+/)
      revision_id = fields[2]
      next
    }
    line ~ /^#{1,3} / {
      revision_id = ""
      next
    }
    revision_id != "" && line ~ /^- archived →/ {
      lower = tolower(line)
      expected = "](artifacts/journal.md#revision-" tolower(revision_id) ")"
      linked = index(lower, expected) > 0
      printf "%s\t%d\n", revision_id, linked
    }
  ' "$tasks"
}

anchor_stats() {
  local journal="$1"
  local normalized_id="$2"
  local revision_id="$3"
  awk -v anchor="<a id=\"revision-${normalized_id}\"></a>" \
    -v target="$(printf '%s' "$revision_id" | tr '[:lower:]' '[:upper:]')" '
    function visible(value, start, rest, ending) {
      if (in_comment) {
        ending = index(value, "-->")
        if (!ending) return ""
        value = substr(value, ending + 3)
        in_comment = 0
      }
      while ((start = index(value, "<!--")) > 0) {
        rest = substr(value, start + 4)
        ending = index(rest, "-->")
        if (ending) {
          value = substr(value, 1, start - 1) substr(rest, ending + 3)
        } else {
          value = substr(value, 1, start - 1)
          in_comment = 1
          break
        }
      }
      return value
    }
    {
      line = visible($0)
      if (line == "") next
      if (line ~ /^[[:space:]]*(```|~~~)/) {
        in_fence = !in_fence
        next
      }
      if (in_fence) next
    }
    line == anchor {
      anchors++
      waiting = 1
      next
    }
    waiting && line ~ /^[[:space:]]*$/ { next }
    waiting {
      upper = toupper(line)
      if (upper ~ "^#{2,3} " target "([[:space:]]|$)") valid++
      waiting = 0
    }
    END { printf "%d\t%d\n", anchors + 0, valid + 0 }
  ' "$journal"
}

legacy_heading_count() {
  local journal="$1"
  local revision_id="$2"
  awk -v target="$(printf '%s' "$revision_id" | tr '[:lower:]' '[:upper:]')" '
    function visible(value, start, rest, ending) {
      if (in_comment) {
        ending = index(value, "-->")
        if (!ending) return ""
        value = substr(value, ending + 3)
        in_comment = 0
      }
      while ((start = index(value, "<!--")) > 0) {
        rest = substr(value, start + 4)
        ending = index(rest, "-->")
        if (ending) {
          value = substr(value, 1, start - 1) substr(rest, ending + 3)
        } else {
          value = substr(value, 1, start - 1)
          in_comment = 1
          break
        }
      }
      return value
    }
    {
      line = visible($0)
      if (line == "") next
      if (line ~ /^[[:space:]]*(```|~~~)/) {
        in_fence = !in_fence
        next
      }
      if (in_fence) next
      upper = toupper(line)
      if (upper ~ "^#{2,3} " target "([[:space:]]|$)") count++
    }
    END { print count + 0 }
  ' "$journal"
}

task_context() {
  local hub="$1"
  local project_path="$2"
  local tasks="$hub/$project_path/tasks.md"
  [ -f "$tasks" ] || {
    printf 'tasks not found: %s\n' "$tasks" >&2
    exit 3
  }

  awk '
    function visible(value, start, rest, ending) {
      if (in_comment) {
        ending = index(value, "-->")
        if (!ending) return ""
        value = substr(value, ending + 3)
        in_comment = 0
      }
      while ((start = index(value, "<!--")) > 0) {
        rest = substr(value, start + 4)
        ending = index(rest, "-->")
        if (ending) {
          value = substr(value, 1, start - 1) substr(rest, ending + 3)
        } else {
          value = substr(value, 1, start - 1)
          in_comment = 1
          break
        }
      }
      sub(/[[:space:]]+$/, "", value)
      return value
    }

    {
      line = visible($0)
      if (line == "") next
      if (line ~ /^[[:space:]]*(```|~~~)/) {
        in_fence = !in_fence
        next
      }
      if (in_fence) next

      if (line ~ /^## Revisions[[:space:]]*$/) {
        in_revisions = 1
        in_tasks = 0
        next
      }
      if (line ~ /^## /) {
        in_revisions = 0
        in_tasks = line !~ /^## (Status|Notes|Context)([[:space:]]|$)/
        next
      }

      if (in_revisions && line ~ /^### [Rr][0-9]+[A-Za-z]*/) {
        lower = tolower(line)
        if (lower ~ /\[open[^]]*\][[:space:]]*$/) {
          open_revisions++
          if (open_revisions <= 20) {
            printf "REVISION\t%d\t%s\n", NR, line
          }
        }
        next
      }

      if (in_tasks && line ~ /^[[:space:]]*- \[[ xX]\]/) {
        total++
        lower = tolower(line)
        if (lower ~ /^[[:space:]]*- \[x\]/) {
          done++
        } else {
          open_tasks++
          if (open_tasks <= 20) {
            printf "TASK\t%d\t%s\n", NR, line
          }
        }
      }
    }
    END {
      printf "SUMMARY\t%d\t%d\t%d\t%d\n", done + 0, total + 0, \
        open_tasks + 0, open_revisions + 0
    }
  ' "$tasks"
}

registry_rows() {
  local registry="$1"
  local source="$2"
  [ -f "$registry" ] || return 0

  awk -F '|' -v source="$source" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }

    /^## / {
      section = substr($0, 4)
      next
    }

    /^\|/ {
      name = trim($2)
      path = trim($3)
      status = trim($5)
      if (name == "" || name == "short-name" || name ~ /^[-:[:space:]]+$/) next
      printf "%s\t%s\t%s\t%s\t%s\n", source, section, name, path, status
    }
  ' "$registry"
}

audit() {
  local mode="$1"
  local hub="$2"
  local filter="${3:-}"
  local registry_only=0
  if [ "$filter" = registry ]; then
    registry_only=1
    filter=""
  fi
  local index="$hub/index.md"
  local archive="$hub/archive.md"

  [ -f "$index" ] || return 0

  local temp_dir
  temp_dir="$(mktemp -d)"
  trap "rm -rf '$temp_dir'" EXIT

  {
    registry_rows "$index" active
    registry_rows "$archive" archive
  } > "$temp_dir/rows.tsv"
  awk -F '\t' '
    { count[$3]++ }
    END {
      for (name in count) {
        if (count[name] > 1) print name
      }
    }
  ' "$temp_dir/rows.tsv" | sort > "$temp_dir/duplicates.txt"

  local detailed_total=0
  local repair_total=0
  local broken_total=0
  local retire_total=0
  local state_conflict_total=0
  local oversized_total=0
  local candidate_total=0
  local duplicate_total
  if [ -n "$filter" ]; then
    duplicate_total="$(grep -Fxc "$filter" "$temp_dir/duplicates.txt" || true)"
  else
    duplicate_total="$(wc -l < "$temp_dir/duplicates.txt" | tr -d '[:space:]')"
  fi

  while IFS=$'\t' read -r source section name relative_path status; do
    [ -n "$name" ] || continue
    if [ -n "$filter" ] && [ "$name" != "$filter" ]; then
      continue
    fi

    relative_path="${relative_path//\`/}"
    local tasks="$hub/$relative_path/tasks.md"
    local bytes=0
    local detailed=0
    local open_revisions=0
    local repairs=0
    local broken=0
    local tasks_exists=0
    if [ -f "$tasks" ]; then
      tasks_exists=1
      bytes="$(wc -c < "$tasks" | tr -d '[:space:]')"
      IFS=$'\t' read -r detailed open_revisions < <(revision_stats "$tasks")

      local journal="$hub/$relative_path/artifacts/journal.md"
      while IFS=$'\t' read -r revision_id linked; do
        [ -n "$revision_id" ] || continue
        local normalized_id
        normalized_id="$(printf '%s' "$revision_id" | tr '[:upper:]' '[:lower:]')"
        local anchor_count=0
        local valid_anchor_count=0
        local heading_count=0
        if [ -f "$journal" ]; then
          IFS=$'\t' read -r anchor_count valid_anchor_count < <(
            anchor_stats "$journal" "$normalized_id" "$revision_id"
          )
          heading_count="$(legacy_heading_count "$journal" "$revision_id")"
        fi

        if [ "$anchor_count" -gt 1 ] ||
          { [ "$anchor_count" -eq 1 ] && [ "$valid_anchor_count" -ne 1 ]; } ||
          { [ "$anchor_count" -eq 0 ] && [ "$heading_count" -ne 1 ]; }; then
          broken=$((broken + 1))
        elif [ "$linked" -eq 0 ] || [ "$anchor_count" -eq 0 ]; then
          repairs=$((repairs + 1))
        fi
      done < <(pointer_records "$tasks")
    fi

    local oversized=0
    if [ "$bytes" -gt 20480 ]; then
      oversized=1
    fi

    local registry_action="-"
    local duplicate=0
    local status_lower
    status_lower="$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')"
    if grep -Fxq "$name" "$temp_dir/duplicates.txt"; then
      duplicate=1
    fi

    local state_conflict=0
    if [ "$tasks_exists" -eq 0 ] ||
      { [ "$source" = archive ] && { [ "$status_lower" != done ] || [ "$open_revisions" -gt 0 ]; }; } ||
      { [ "$source" = active ] && [ "$status_lower" = done ] && [ "$open_revisions" -gt 0 ]; } ||
      { [ "$source" = active ] && [ "$section" = Archive ] &&
        { [ "$status_lower" != done ] || [ "$open_revisions" -gt 0 ]; }; }; then
      state_conflict=1
      state_conflict_total=$((state_conflict_total + 1))
    fi

    if [ "$duplicate" -eq 1 ]; then
      registry_action="duplicate-registry-row"
    elif [ "$tasks_exists" -eq 0 ]; then
      registry_action="missing-tasks"
    elif [ "$state_conflict" -eq 1 ]; then
      if [ "$source" = active ] && [ "$section" != Archive ]; then
        registry_action="reopen-status"
      else
        registry_action="reactivate"
      fi
    elif [ "$source" = active ] && [ "$section" = Archive ]; then
      registry_action="migrate-legacy-archive"
      retire_total=$((retire_total + 1))
    elif [ "$source" = active ] && [ "$status_lower" = done ]; then
      registry_action="retire"
      retire_total=$((retire_total + 1))
    fi

    if [ "$registry_only" -eq 1 ] && [ "$registry_action" = "-" ]; then
      continue
    fi
    if [ "$detailed" -eq 0 ] && [ "$repairs" -eq 0 ] && [ "$broken" -eq 0 ] && [ "$oversized" -eq 0 ] && [ "$registry_action" = "-" ]; then
      continue
    fi

    candidate_total=$((candidate_total + 1))
    detailed_total=$((detailed_total + detailed))
    repair_total=$((repair_total + repairs))
    broken_total=$((broken_total + broken))
    oversized_total=$((oversized_total + oversized))
    printf '%s\n' "$name" >> "$temp_dir/projects.txt"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$name" "$source" "$section" "$bytes" "$detailed" "$repairs" "$broken" "$open_revisions" "$registry_action" \
      >> "$temp_dir/report.tsv"
  done < "$temp_dir/rows.tsv"

  [ "$candidate_total" -gt 0 ] || return 0

  sort -u "$temp_dir/projects.txt" > "$temp_dir/projects.sorted"
  local project_count projects
  project_count="$(wc -l < "$temp_dir/projects.sorted" | tr -d '[:space:]')"
  projects="$(sed -n '1,8p' "$temp_dir/projects.sorted" | paste -sd, -)"
  if [ "$project_count" -gt 8 ]; then
    projects="${projects},+$((project_count - 8)) more"
  fi

  if [ "$mode" = hook ]; then
    printf 'todo-list: archive candidates — detailed_done_revisions=%d; tombstone_link_repairs=%d; broken_tombstones=%d; done_index_rows=%d; state_conflicts=%d; registry_duplicates=%d; oversized_tasks=%d; projects=%s. Run /todo-archive to review.\n' \
      "$detailed_total" "$repair_total" "$broken_total" "$retire_total" "$state_conflict_total" "$duplicate_total" "$oversized_total" "$projects"
    return 0
  fi

  printf 'project\tsource\tsection\ttasks_bytes\tdetailed_done\tlink_repairs\tbroken_tombstones\topen_revisions\tregistry_action\n'
  sort "$temp_dir/report.tsv"
  printf 'TOTAL\t-\t-\t-\t%d\t%d\t%d\t-\tretire=%d,state_conflicts=%d,duplicate_names=%d\n' \
    "$detailed_total" "$repair_total" "$broken_total" "$retire_total" \
    "$state_conflict_total" "$duplicate_total"
}

lookup_revision() {
  local hub="$1"
  local project_path="$2"
  local revision_id="$3"
  local tasks="$hub/$project_path/tasks.md"
  local journal="$hub/$project_path/artifacts/journal.md"

  revision_id="$(printf '%s' "$revision_id" | tr '[:lower:]' '[:upper:]')"
  [[ "$revision_id" =~ ^R[0-9]+[A-Z]*$ ]] || {
    printf 'invalid revision id: %s\n' "$revision_id" >&2
    exit 2
  }

  if [ -f "$tasks" ]; then
    local task_heading_count=0
    local task_has_pointer=0
    IFS=$'\t' read -r task_heading_count task_has_pointer < <(
      awk -v target="$revision_id" '
        function visible(value, start, rest, ending) {
          if (in_comment) {
            ending = index(value, "-->")
            if (!ending) return ""
            value = substr(value, ending + 3)
            in_comment = 0
          }
          while ((start = index(value, "<!--")) > 0) {
            rest = substr(value, start + 4)
            ending = index(rest, "-->")
            if (ending) {
              value = substr(value, 1, start - 1) substr(rest, ending + 3)
            } else {
              value = substr(value, 1, start - 1)
              in_comment = 1
              break
            }
          }
          return value
        }
        {
          line = visible($0)
          if (line == "") next
          if (line ~ /^[[:space:]]*(```|~~~)/) {
            in_fence = !in_fence
            next
          }
          if (in_fence) next
        }
        line ~ /^## Revisions[[:space:]]*$/ {
          in_revisions = 1
          current = 0
          next
        }
        in_revisions && line ~ /^## / {
          in_revisions = 0
          current = 0
          next
        }
        !in_revisions { next }
        line ~ /^### [Rr][0-9]+[A-Za-z]*/ {
          upper = toupper(line)
          current = upper ~ "^### " target "([[:space:]]|$)"
          if (current) count++
          next
        }
        line ~ /^### / { current = 0 }
        current && line ~ /^- archived →/ { pointer = 1 }
        END { printf "%d\t%d\n", count + 0, pointer + 0 }
      ' "$tasks"
    )

    if [ "$task_heading_count" -gt 1 ]; then
      printf '%s has multiple task headings in %s\n' "$revision_id" "$tasks" >&2
      exit 5
    fi
    if [ "$task_heading_count" -eq 1 ] && [ "$task_has_pointer" -eq 0 ]; then
      awk -v target="$revision_id" '
        function visible(value, start, rest, ending) {
          if (in_comment) {
            ending = index(value, "-->")
            if (!ending) return ""
            value = substr(value, ending + 3)
            in_comment = 0
          }
          while ((start = index(value, "<!--")) > 0) {
            rest = substr(value, start + 4)
            ending = index(rest, "-->")
            if (ending) {
              value = substr(value, 1, start - 1) substr(rest, ending + 3)
            } else {
              value = substr(value, 1, start - 1)
              in_comment = 1
              break
            }
          }
          return value
        }
        {
          line = visible($0)
          if (line == "") next
          if (found) {
            if (line ~ /^[[:space:]]*(```|~~~)/) {
              in_fence = !in_fence
              print
              next
            }
            if (in_fence) {
              print
              next
            }
            if (line ~ /^#{1,3} /) exit
            print
            next
          }

          if (line ~ /^[[:space:]]*(```|~~~)/) {
            in_fence = !in_fence
            next
          }
          if (in_fence) next
          if (line ~ /^## Revisions[[:space:]]*$/) {
            in_revisions = 1
            next
          }
          if (in_revisions && line ~ /^## /) {
            in_revisions = 0
            next
          }
          if (in_revisions) {
            upper = toupper(line)
            if (upper ~ "^### " target "([[:space:]]|$)") {
              found = 1
              print
            }
          }
        }
      ' "$tasks"
      return 0
    fi
  fi

  [ -f "$journal" ] || {
    printf 'journal not found: %s\n' "$journal" >&2
    exit 3
  }

  local anchor
  anchor="<a id=\"revision-$(printf '%s' "$revision_id" | tr '[:upper:]' '[:lower:]')\"></a>"

  local normalized_id anchor_count valid_anchor_count
  normalized_id="$(printf '%s' "$revision_id" | tr '[:upper:]' '[:lower:]')"
  IFS=$'\t' read -r anchor_count valid_anchor_count < <(
    anchor_stats "$journal" "$normalized_id" "$revision_id"
  )
  if [ "$anchor_count" -gt 1 ]; then
    printf '%s has multiple anchors in %s\n' "$revision_id" "$journal" >&2
    exit 5
  fi
  if [ "$anchor_count" -eq 1 ] && [ "$valid_anchor_count" -ne 1 ]; then
    printf '%s anchor does not immediately identify its journal heading in %s\n' \
      "$revision_id" "$journal" >&2
    exit 5
  fi

  local result=""
  if [ "$anchor_count" -eq 1 ]; then
    result="$(
      awk -v anchor="$anchor" '
        function visible(value, start, rest, ending) {
          if (in_comment) {
            ending = index(value, "-->")
            if (!ending) return ""
            value = substr(value, ending + 3)
            in_comment = 0
          }
          while ((start = index(value, "<!--")) > 0) {
            rest = substr(value, start + 4)
            ending = index(rest, "-->")
            if (ending) {
              value = substr(value, 1, start - 1) substr(rest, ending + 3)
            } else {
              value = substr(value, 1, start - 1)
              in_comment = 1
              break
            }
          }
          return value
        }
        {
          line = visible($0)
          if (line == "") next
          if (line ~ /^[[:space:]]*(```|~~~)/) {
            in_fence = !in_fence
            if (found) print
            next
          }
          if (in_fence) {
            if (found) print
            next
          }
        }
        line == anchor {
          found = 1
          print
          next
        }
        found && line ~ /^<a id="revision-r[0-9]+[A-Za-z]*"><\/a>$/ { exit }
        found && seen_heading && line ~ /^#{1,3} / { exit }
        found {
          print
          upper = toupper(line)
          if (upper ~ /^#{2,3} R[0-9]+[A-Z]*([[:space:]]|$)/) seen_heading = 1
        }
      ' "$journal"
    )"
  else
    local heading_count
    heading_count="$(legacy_heading_count "$journal" "$revision_id")"
    if [ "$heading_count" -gt 1 ]; then
      printf '%s has multiple legacy headings in %s\n' "$revision_id" "$journal" >&2
      exit 5
    fi
    if [ "$heading_count" -eq 1 ]; then
      result="$(
        awk -v target="$(printf '%s' "$revision_id" | tr '[:lower:]' '[:upper:]')" '
          function visible(value, start, rest, ending) {
            if (in_comment) {
              ending = index(value, "-->")
              if (!ending) return ""
              value = substr(value, ending + 3)
              in_comment = 0
            }
            while ((start = index(value, "<!--")) > 0) {
              rest = substr(value, start + 4)
              ending = index(rest, "-->")
              if (ending) {
                value = substr(value, 1, start - 1) substr(rest, ending + 3)
              } else {
                value = substr(value, 1, start - 1)
                in_comment = 1
                break
              }
            }
            return value
          }
          {
            line = visible($0)
            if (line == "") next
            if (line ~ /^[[:space:]]*(```|~~~)/) {
              in_fence = !in_fence
              if (found) print
              next
            }
            if (in_fence) {
              if (found) print
              next
            }
            upper = toupper(line)
            if (!found && upper ~ "^#{2,3} " target "([[:space:]]|$)") {
              found = 1
            } else if (found && (line ~ /^<a id="revision-r[0-9]+[A-Za-z]*"><\/a>$/ || line ~ /^#{1,3} /)) {
              exit
            }
            if (found) print
          }
        ' "$journal"
      )"
    fi
  fi

  [ -n "$result" ] || {
    printf '%s not found in %s\n' "$revision_id" "$journal" >&2
    exit 4
  }
  printf '%s\n' "$result"
}

mode="${1:-}"
case "$mode" in
  audit)
    shift
    hub="$(expand_hub "${1:-${TODO_HUB:-$HOME/todo}}")"
    filter="${2:-}"
    audit audit "$hub" "$filter"
    ;;
  hook)
    shift
    hub="$(expand_hub "${1:-${TODO_HUB:-$HOME/todo}}")"
    audit hook "$hub"
    ;;
  context)
    [ "$#" -eq 3 ] || usage
    task_context "$(expand_hub "$2")" "$3"
    ;;
  lookup)
    [ "$#" -eq 4 ] || usage
    lookup_revision "$(expand_hub "$2")" "$3" "$4"
    ;;
  *)
    usage
    ;;
esac
