#!/usr/bin/env bash
# Every task counter in the plugin applies one rule (todo-conventions § Counting tasks), so
# they must agree on the same tasks.md: graph-report.py `tasks` and `export`,
# archive-report.sh `context`, the infographic's parse_tasks, and the shell snippet
# printed in todo-conventions. Crafted fixtures pin the expected counts too, so counters
# that agree on a wrong answer still fail.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRAPH="$ROOT/skills/todo-graph/scripts/graph-report.py"
ARCHIVE="$ROOT/skills/todo-archive/scripts/archive-report.sh"
INFOGRAPHIC="$ROOT/skills/todo-infographic/scripts/refresh-infographic.py"
CONVENTIONS="$ROOT/skills/todo-conventions/SKILL.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/todo-count-agreement.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export PYTHONDONTWRITEBYTECODE=1

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

# The shell snippet under § Counting tasks: the bash block that runs awk.
awk '
  /^## / { in_section = ($0 == "## Counting tasks"); next }
  !in_section { next }
  /^```bash$/ { block = ""; in_block = 1; next }
  in_block && /^```$/ { if (block ~ /awk \047/) { printf "%s", block; exit } in_block = 0; next }
  in_block { block = block $0 "\n" }
' "$CONVENTIONS" > "$TMP/conventions-count.sh"
grep -q "tasks.md" "$TMP/conventions-count.sh" ||
  fail "todo-conventions § Counting tasks must carry the awk snippet for a bare tasks.md"

HUB="$TMP/hub"
mkdir -p "$HUB/projects/work"
{
  printf '# Project Index\n\n## Work\n\n'
  printf '| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |\n'
  printf '|---|---|---|---|---|---|---|---|---|\n'
} > "$HUB/index.md"
{
  printf '# Project Archive\n\n## Work\n\n'
  printf '| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |\n'
  printf '|---|---|---|---|---|---|---|---|---|\n'
} > "$HUB/archive.md"

# name|expected "done total open_revisions", or "-" to require agreement only.
EXPECTED="$TMP/expected"
: > "$EXPECTED"
add_project() {
  local name="$1" expected="$2"
  mkdir -p "$HUB/projects/work/$name"
  printf '# Project: %s\n\n## Goal\nCount agreement fixture.\n' "$name" \
    > "$HUB/projects/work/$name/plan.md"
  printf '| %s | projects/work/%s | - | in-progress | - | - | - | - | - |\n' \
    "$name" "$name" >> "$HUB/index.md"
  printf '%s|%s\n' "$name" "$expected" >> "$EXPECTED"
}

# `### Phase` under `## Tasks`, `[X]`, link and plain bullets, near-miss checkboxes,
# excluded sections, a pre-heading checkbox, and Revisions checkboxes and open tags.
add_project phases-under-tasks "4 8 2"
cat > "$HUB/projects/work/phases-under-tasks/tasks.md" <<'TASKS'
# Tasks
- [x] before any level-2 heading is not a task

## Status
- [ ] status box
- [x] status done

## Tasks

### Phase 1 — Foundation
- [x] one
- [X] two, upper-case done

### Phase 6a — Cutover
- [ ] three
  - [ ] four, nested
- [link](research/notes.md)
- plain bullet
* [ ] star bullet is not a task
- [x]no space is not a task
- [ ]
-  [ ]  five, extra spaces

### Follow-ups
- [x] six, loose

## Revisions
### R1 ⟵ Task 1.1 — first   [done 2026-01-01]
- [x] seven
### R2 ⟵ Task 6a.1 — second   [OPEN]
- [ ] eight
### R3 — third   [open — blocked on vendor]
### R4 — fourth   [opened]
TASKS

# HTML comments (inline, multi-line, mid-line) and fences (both characters, longer
# closers, an info string that does not close, an inner shorter fence, indentation).
add_project fences-comments "3 7 0"
cat > "$HUB/projects/work/fences-comments/tasks.md" <<'TASKS'
# Tasks

## Tasks
- [x] visible one
<!-- - [ ] hidden in a comment -->
<!--
- [ ] hidden in a multi-line comment
-->
- [ ] visible two <!-- trailing comment -->
text <!-- opens mid-line
- [ ] hidden after a mid-line opener
--> - [ ] visible three, after the closer

```
- [ ] hidden in a backtick fence
```js
- [ ] still hidden: a closer takes no info string
```
~~~~
- [ ] hidden in a tilde fence
~~~
- [ ] still hidden: the closer is shorter
```
- [ ] still hidden: the closer uses the other character
~~~~~
- [x] visible four
````markdown
```
- [ ] hidden: an inner shorter fence
````
<!-- ``` -->
- [X] visible five: a fence opener inside a comment is inert
```text
<!-- an inert comment opener inside a fence
```
- [ ] visible six: the fenced opener did not start a comment
   ```
   - [ ] hidden in an indented fence
   ```

## Notes
- [ ] a note is not a task

## CONTEXT
- [x] context in any case is not a task

## Status — current
- [ ] visible seven: only the whole heading text is excluded
TASKS

# A level-3 heading inside a level-2 phase is a subsection of it.
add_project level2-phases "1 3 0"
cat > "$HUB/projects/work/level2-phases/tasks.md" <<'TASKS'
# Tasks

## Phase 1 — Setup
- [x] a
### Phase 3 — a subsection of Phase 1
- [ ] b

## Phase 2b — Rollout
- [ ] c

## Revisions
TASKS

# A decimal phase number is its own phase, with IDs like 4.5.1.
add_project decimal-phases "2 4 0"
cat > "$HUB/projects/work/decimal-phases/tasks.md" <<'TASKS'
# Tasks

## Phase 4 — Gateway
- [x] a
- [ ] b

## Phase 4.5 — Degradation
- [x] c
- [ ] d
TASKS

# No level-2 section at all: nothing counts.
add_project no-sections "0 0 0"
printf '# Tasks\n- [ ] a\n- [x] b\n### Phase 1\n- [ ] c\n' \
  > "$HUB/projects/work/no-sections/tasks.md"

# The shipped files must agree too, whatever they currently hold.
add_project seed-template "-"
cp "$ROOT/seed/templates/tasks.md" "$HUB/projects/work/seed-template/tasks.md"
add_project seed-example "-"
cp "$ROOT/seed/projects/work/example-feature/tasks.md" \
  "$HUB/projects/work/seed-example/tasks.md"

cat > "$TMP/infographic-count.py" <<'PY'
import importlib.util
import sys

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("refresh_infographic", sys.argv[1])
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
with open(sys.argv[2], encoding="utf-8") as handle:
    model = module.parse_tasks(handle.read())
print(f"{model.done} {model.total}")
for phase in model.phases:
    if phase.total:
        print(f"PHASE {phase.key} {phase.done} {phase.total}")
PY

python3 "$GRAPH" export "$HUB" tsv > "$TMP/export.tsv" ||
  fail "export failed on the agreement hub"

checked=0
while IFS='|' read -r name expected; do
  dir="$HUB/projects/work/$name"

  python3 "$GRAPH" tasks "$HUB" "$name" > "$TMP/$name.tasks" ||
    fail "$name: graph-report.py tasks exited non-zero"
  graph="$(awk -F '\t' '$1 == "SUMMARY" {
    sub(/^done=/, "", $4); sub(/^total=/, "", $5); sub(/^open_revisions=/, "", $6)
    print $4, $5, $6 }' "$TMP/$name.tasks")"
  rows="$(awk -F '\t' '$1 == "TASK" { total++; if ($3 == "done") done++ }
    END { print done + 0, total + 0 }' "$TMP/$name.tasks")"

  export_counts="$(awk -F '\t' -v name="$name" '$1 == "NODE" && $2 == name {
    sub(/^tasks=/, "", $7); sub(/^open_revisions=/, "", $8); split($7, c, "/")
    print c[1], c[2], $8 }' "$TMP/export.tsv")"

  archive="$(bash "$ARCHIVE" context "$HUB" "projects/work/$name" |
    awk -F '\t' '$1 == "SUMMARY" { print $2, $3, $5 }')"

  snippet="$(cd "$dir" && bash "$TMP/conventions-count.sh" | tr '/' ' ')"

  python3 "$TMP/infographic-count.py" "$INFOGRAPHIC" "$dir/tasks.md" > "$TMP/$name.info" ||
    fail "$name: the infographic parse_tasks failed"
  infographic="$(head -n 1 "$TMP/$name.info")"

  [ -n "$graph" ] || fail "$name: graph-report.py tasks printed no SUMMARY"
  graph_counts="${graph% *}"
  [ "$export_counts" = "$graph" ] ||
    fail "$name: export NODE '$export_counts' disagrees with tasks '$graph'"
  [ "$archive" = "$graph" ] ||
    fail "$name: archive-report.sh context '$archive' disagrees with graph-report.py '$graph'"
  [ "$rows" = "$graph_counts" ] ||
    fail "$name: TASK rows '$rows' disagree with SUMMARY '$graph_counts'"
  [ "$snippet" = "$graph_counts" ] ||
    fail "$name: the todo-conventions snippet '$snippet' disagrees with graph-report.py '$graph_counts'"
  [ "$infographic" = "$graph_counts" ] ||
    fail "$name: refresh-infographic.py '$infographic' disagrees with graph-report.py '$graph_counts'"
  if [ "$expected" != "-" ] && [ "$graph" != "$expected" ]; then
    fail "$name: every counter says '$graph', the canonical rule says '$expected'"
  fi

  # Phase totals: the infographic's phases and the graph's <phase>.<n> IDs agree.
  graph_phases="$(awk -F '\t' '$1 == "TASK" && $2 ~ /^[0-9]+(\.[0-9]+)?[a-z]?\.[0-9]+$/ {
      key = $2; sub(/\.[0-9]+$/, "", key); key = "phase-" key
      if (!(key in total)) order[++n] = key
      total[key]++; if ($3 == "done") done[key]++ }
    END { for (i = 1; i <= n; i++) print "PHASE", order[i], done[order[i]] + 0, total[order[i]] }' \
    "$TMP/$name.tasks")"
  info_phases="$(sed -n '2,$p' "$TMP/$name.info")"
  [ "$graph_phases" = "$info_phases" ] ||
    fail "$name: phase totals disagree — graph: [$graph_phases] infographic: [$info_phases]"

  checked=$((checked + 1))
done < "$EXPECTED"

[ "$checked" -eq 7 ] || fail "checked $checked fixtures instead of 7"
printf 'ok - %d fixtures agree across five counters\n' "$checked"
printf 'count agreement contract tests passed\n'
