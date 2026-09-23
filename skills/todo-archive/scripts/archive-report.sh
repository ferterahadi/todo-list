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

# Visible-line scanner for the tasks.md counters (`context`, `audit`). It applies the hub's
# canonical rules (todo-conventions § Counting tasks), matching graph-report.py
# `visible_lines`: HTML comments are removed, even mid-line; a fence opens on three or
# more backticks or tildes and closes only on a run of the same character at least as
# long; blank lines are skipped; `line` holds the visible text without trailing space.
TASK_SCAN_AWK='
  function visible(value,   out, position) {
    out = ""
    while (value != "") {
      if (in_comment) {
        position = index(value, "-->")
        if (!position) return out
        value = substr(value, position + 3)
        in_comment = 0
        continue
      }
      position = index(value, "<!--")
      if (!position) return out value
      out = out substr(value, 1, position - 1)
      value = substr(value, position + 4)
      in_comment = 1
    }
    return out
  }
  function run_length(value, char,   count) {
    count = 0
    while (substr(value, count + 1, 1) == char) count++
    return count
  }
  function scan(raw,   stripped, char, count) {
    if (fence_char != "") {
      stripped = raw
      sub(/^[[:space:]]+/, "", stripped)
      count = run_length(stripped, fence_char)
      if (count >= fence_len && substr(stripped, count + 1) ~ /^[[:space:]]*$/) fence_char = ""
      return 0
    }
    line = visible(raw)
    stripped = line
    sub(/^[[:space:]]+/, "", stripped)
    char = substr(stripped, 1, 1)
    if (char == "`" || char == "~") {
      count = run_length(stripped, char)
      if (count >= 3) {
        fence_char = char
        fence_len = count
        return 0
      }
    }
    sub(/[[:space:]]+$/, "", line)
    return line != ""
  }
  function section_title(value) {
    if (value !~ /^##[[:space:]]+[^[:space:]]/) return ""
    sub(/^##[[:space:]]+/, "", value)
    return tolower(value)
  }
  function is_open_revision(value,   lower) {
    lower = tolower(value)
    return lower ~ /^###[[:space:]]+r[0-9]+[a-z]*([^a-z0-9_]|$)/ &&
      lower ~ /\[[[:space:]]*open([[:space:]]+[^]]*)?[[:space:]]*\][[:space:]]*$/
  }
  # `[fixed — awaiting verify]`: the fix landed but its verify checkbox is still open.
  function is_pending_verify(value,   lower) {
    lower = tolower(value)
    return lower ~ /^###[[:space:]]+r[0-9]+[a-z]*([^a-z0-9_]|$)/ &&
      lower ~ /\[[[:space:]]*fixed[^]]*awaiting[[:space:]]+verify[^]]*\][[:space:]]*$/
  }
'

# One pass over a project's tasks.md and, when it has tombstones, one pass over its
# journal. Prints: detailed_done  open_revisions  link_repairs  broken_tombstones
# open_tasks  pending_verify. open_tasks follows the canonical count, so Revisions
# checkboxes are included.
# The journal side keeps the exact matching rules `lookup` uses (anchor_stats and
# legacy_heading_count), so an audit verdict and a lookup always agree.
project_stats() {
  TASKS_FILE="$1" JOURNAL_FILE="$2" awk "$TASK_SCAN_AWK"'
    function finish_entry() {
      if (in_revision && is_done && has_detail && !has_pointer) detailed_done++
      in_revision = 0
      is_done = 0
      has_detail = 0
      has_pointer = 0
    }
    function journal_visible(value, start, rest, ending) {
      if (journal_comment) {
        ending = index(value, "-->")
        if (!ending) return ""
        value = substr(value, ending + 3)
        journal_comment = 0
      }
      while ((start = index(value, "<!--")) > 0) {
        rest = substr(value, start + 4)
        ending = index(rest, "-->")
        if (ending) {
          value = substr(value, 1, start - 1) substr(rest, ending + 3)
        } else {
          value = substr(value, 1, start - 1)
          journal_comment = 1
          break
        }
      }
      return value
    }
    # The lowercase revision id of a `## R<n>` / `### R<n>` heading, else "".
    function heading_id(value,   rest, space) {
      if (substr(value, 1, 3) == "## ") rest = substr(value, 4)
      else if (substr(value, 1, 4) == "### ") rest = substr(value, 5)
      else return ""
      space = match(rest, /[[:space:]]/)
      return tolower(space ? substr(rest, 1, space - 1) : rest)
    }

    BEGIN {
      tasks_file = ENVIRON["TASKS_FILE"]
      journal_file = ENVIRON["JOURNAL_FILE"]
      while ((getline raw < tasks_file) > 0) {
        if (!scan(raw)) continue
        title = section_title(line)
        if (title != "") {
          finish_entry()
          in_revisions = title == "revisions"
          counting = title != "status" && title != "notes" && title != "context"
          revision_id = ""
          continue
        }
        if (counting && line ~ /^[[:space:]]*-[[:space:]]+\[ \][[:space:]]/) open_tasks++
        if (!in_revisions) continue

        if (is_open_revision(line)) open_revisions++
        if (is_pending_verify(line)) pending_verify++
        if (line ~ /^###[[:space:]]+[Rr][0-9]+/) {
          finish_entry()
          in_revision = 1
          lower = tolower(line)
          is_done = lower ~ /\[done[^]]*\][[:space:]]*$/
          split(line, fields, /[[:space:]]+/)
          revision_id = fields[2]
          continue
        }
        if (line ~ /^(#|##|###)[[:space:]]/) {
          if (line ~ /^###[[:space:]]/) finish_entry()
          revision_id = ""
          if (line ~ /^###[[:space:]]/) continue
        }
        if (line ~ /^- archived →/) {
          if (in_revision) has_pointer = 1
          if (revision_id != "") {
            pointers++
            pointer_id[pointers] = tolower(revision_id)
            expected = "](artifacts/journal.md#revision-" tolower(revision_id) ")"
            pointer_linked[pointers] = index(tolower(line), expected) > 0
            wanted[tolower(revision_id)] = 1
          }
          continue
        }
        if (in_revision) has_detail = 1
      }
      close(tasks_file)
      finish_entry()

      if (pointers && journal_file != "") {
        while ((getline raw < journal_file) > 0) {
          value = journal_visible(raw)
          if (value == "") continue
          if (value ~ /^[[:space:]]*(```|~~~)/) {
            journal_fence = !journal_fence
            continue
          }
          if (journal_fence) continue
          if (value ~ /^<a id="revision-[^"]*"><\/a>$/) {
            anchor = substr(value, 17, length(value) - 22)
            if (anchor in wanted) {
              anchors[anchor]++
              waiting = anchor
              continue
            }
          }
          if (waiting != "") {
            if (value ~ /^[[:space:]]*$/) continue
            if (heading_id(value) == waiting) valid_anchors[waiting]++
            waiting = ""
          }
          id = heading_id(value)
          if (id != "" && (id in wanted)) headings[id]++
        }
        close(journal_file)
      }

      for (i = 1; i <= pointers; i++) {
        id = pointer_id[i]
        anchor_count = anchors[id] + 0
        valid_count = valid_anchors[id] + 0
        heading_count = headings[id] + 0
        if (anchor_count > 1 ||
          (anchor_count == 1 && valid_count != 1) ||
          (anchor_count == 0 && heading_count != 1)) {
          broken++
        } else if (!pointer_linked[i] || anchor_count == 0) {
          repairs++
        }
      }
      printf "%d\t%d\t%d\t%d\t%d\t%d\n", detailed_done + 0, open_revisions + 0, \
        repairs + 0, broken + 0, open_tasks + 0, pending_verify + 0
    }
  '
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

  # Counts follow the canonical rule, so SUMMARY agrees with graph-report.py `tasks`:
  # Revisions checkboxes are real tasks, and `[X]` is done.
  awk "$TASK_SCAN_AWK"'
    {
      if (!scan($0)) next
      title = section_title(line)
      if (title != "") {
        in_revisions = title == "revisions"
        counting = title != "status" && title != "notes" && title != "context"
        next
      }
      if (line ~ /^#+[[:space:]]/) {
        if (in_revisions && is_open_revision(line)) {
          open_revisions++
          if (open_revisions <= 20) printf "REVISION\t%d\t%s\n", NR, line
        }
        next
      }
      if (counting && line ~ /^[[:space:]]*-[[:space:]]+\[[ xX]\][[:space:]]/) {
        total++
        if (line ~ /^[[:space:]]*-[[:space:]]+\[[xX]\]/) {
          done++
        } else {
          open_tasks++
          if (open_tasks <= 20) printf "TASK\t%d\t%s\n", NR, line
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
  # Prefix each row with its duplicate flag and lowercase status (never empty, so tab
  # splitting cannot shift them), so the per-project loop spawns no helper for either.
  awk -F '\t' -v OFS='\t' -v duplicates="$temp_dir/duplicates.txt" '
    BEGIN {
      while ((getline name < duplicates) > 0) duplicate[name] = 1
      close(duplicates)
    }
    {
      status = tolower($5)
      print (($3 in duplicate) ? 1 : 0), (status == "" ? "-" : status), $0
    }
  ' "$temp_dir/rows.tsv" > "$temp_dir/rows.annotated"

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

  while IFS=$'\t' read -r duplicate status_lower source section name relative_path status; do
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
    local open_tasks=0
    local pending_verify=0
    local tasks_exists=0
    if [ -f "$tasks" ]; then
      tasks_exists=1
      bytes="$(wc -c < "$tasks")"
      bytes=$((bytes))
      IFS=$'\t' read -r detailed open_revisions repairs broken open_tasks pending_verify < <(
        project_stats "$tasks" "$hub/$relative_path/artifacts/journal.md"
      )
    fi
    # Unfinished revisions: `[open…]` plus `[fixed — awaiting verify]`. An active `done`
    # row must also have no open real task, so it never retires with open work.
    local unfinished=$((open_revisions + pending_verify))
    local active_open_work=$((unfinished + open_tasks))

    local oversized=0
    if [ "$bytes" -gt 20480 ]; then
      oversized=1
    fi

    local registry_action="-"

    local state_conflict=0
    if [ "$tasks_exists" -eq 0 ] ||
      { [ "$source" = archive ] && { [ "$status_lower" != done ] || [ "$unfinished" -gt 0 ]; }; } ||
      { [ "$source" = active ] && [ "$status_lower" = done ] && [ "$active_open_work" -gt 0 ]; } ||
      { [ "$source" = active ] && [ "$section" = Archive ] &&
        { [ "$status_lower" != done ] || [ "$unfinished" -gt 0 ]; }; }; then
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
  done < "$temp_dir/rows.annotated"

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
