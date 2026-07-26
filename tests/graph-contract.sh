#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRAPH="$ROOT/skills/todo-graph/scripts/graph-report.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/todo-graph-contract.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"
  grep -F -- "$expected" "$file" >/dev/null ||
    fail "$file does not contain: $expected"
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  if grep -F -- "$unexpected" "$file" >/dev/null; then
    fail "$file unexpectedly contains: $unexpected"
  fi
}

snapshot() {
  local hub="$1"
  find "$hub" -type f | LC_ALL=C sort | while IFS= read -r file; do
    cksum "$file"
  done
}

write_tasks() {
  local project_dir="$1"
  local state="${2:-open}"
  mkdir -p "$project_dir"
  if [ "$state" = done ]; then
    cat > "$project_dir/tasks.md" <<'TASKS'
# Tasks

## Status
- [ ] Not started
- [x] Done

## Tasks
- [x] Finish the project

## Revisions
TASKS
  else
    cat > "$project_dir/tasks.md" <<'TASKS'
# Tasks

## Status
- [ ] Not started
- [x] Done

## Tasks
- [ ] Finish the project

## Revisions
TASKS
  fi
}

write_empty_plan() {
  local project_dir="$1"
  mkdir -p "$project_dir"
  cat > "$project_dir/plan.md" <<'PLAN'
# Project

## Goal
Exercise the deterministic graph contract.

## References
- none
PLAN
}

make_clean_hub() {
  local hub="$1"
  mkdir -p "$hub/projects/work"
  cat > "$hub/index.md" <<'INDEX'
# Project Index

## Work

| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |
|---|---|---|---|---|---|---|---|---|
| api | projects/work/api | - | ready | - | - | - | - | legacy-context |
| api-v2 | projects/work/api-v2 | - | ready | - | - | - | - | - |
| consumer | projects/work/consumer | - | ready | - | - | - | - | - |
| legacy-context | projects/work/legacy-context | - | planning | - | - | - | - | - |
| planning-dependent | projects/work/planning-dependent | - | planning | - | - | - | - | - |
INDEX
  cat > "$hub/archive.md" <<'ARCHIVE'
# Project Archive

## Work

| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |
|---|---|---|---|---|---|---|---|---|
| foundation | projects/work/foundation | - | done | - | - | - | - | - |
ARCHIVE

  local name
  for name in api api-v2 consumer legacy-context planning-dependent; do
    write_tasks "$hub/projects/work/$name" open
    write_empty_plan "$hub/projects/work/$name"
  done
  {
    printf '%s\n' \
      '# Project: API v2' \
      '' \
      '## Goal' \
      'Exercise bounded display fields.' \
      '' \
      '## Relationships' \
      '' \
      '| relation | target | reason |' \
      '|---|---|---|'
    printf '| related-to | `legacy-context` | '
    awk 'BEGIN { for (i = 0; i < 600; i++) printf "x" }'
    printf ' |\n'
  } > "$hub/projects/work/api-v2/plan.md"
  write_tasks "$hub/projects/work/foundation" done
  write_empty_plan "$hub/projects/work/foundation"

  cat > "$hub/projects/work/api/plan.md" <<'PLAN'
# Project: API

## Goal
Ship the API after the archived foundation settles.

<!--
## Relationships
| relation | target | reason |
|---|---|---|
| depends-on | missing-comment-target | hidden fixture |
-->

```markdown
## Relationships
| relation | target | reason |
|---|---|---|
| depends-on | missing-fence-target | hidden fixture |
literal <!-- comment opener is inert inside the fence
```

## Relationships

| relation | target | reason |
|---|---|---|
| depends-on | `foundation` | consumes the settled contract |

## References
- none
PLAN
  cat > "$hub/projects/work/consumer/plan.md" <<'PLAN'
# Project: Consumer

## Goal
Consume the API.

## Relationships

| relation | target | reason |
|---|---|---|
| depends-on | `api` | needs the API |

## References
- none
PLAN
  cat > "$hub/projects/work/planning-dependent/plan.md" <<'PLAN'
# Project: Planning dependent

## Goal
Plan work after the foundation.

## Relationships

| relation | target | reason |
|---|---|---|
| depends-on | `foundation` | will consume the contract after planning |
PLAN
}

make_corrupt_hub() {
  local hub="$1"
  mkdir -p "$hub/projects/work"
  cat > "$hub/index.md" <<'INDEX'
# Project Index

## Work

| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |
|---|---|---|---|---|---|---|---|---|
| active-done | projects/work/active-done | - | done | - | - | - | - | - |
| blocked-active | projects/work/blocked-active | - | ready | - | - | - | - | - |
| cycle-a | projects/work/cycle-a | - | ready | - | - | - | - | - |
| cycle-b | projects/work/cycle-b | - | ready | - | - | - | - | - |
| cycle-tail | projects/work/cycle-tail | - | ready | - | - | - | - | - |
| escape | projects/work/escape | - | ready | - | - | - | - | - |
| file-escape | projects/work/file-escape | - | ready | - | - | - | - | - |
| malformed | projects/work/malformed | - | ready | - | - | - | - | - |
| ready-complete | projects/work/ready-complete | - | ready | - | - | - | - | - |
| duplicate-id | projects/work/duplicate-active | - | ready | - | - | - | - | - |
INDEX
  cat > "$hub/archive.md" <<'ARCHIVE'
# Project Archive

## Work

| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |
|---|---|---|---|---|---|---|---|---|
| open-done | projects/work/open-done | - | done | - | - | - | - | - |
| archive-ready | projects/work/archive-ready | - | ready | - | - | - | - | - |
| missing-tasks | projects/work/missing-tasks | - | done | - | - | - | - | - |
| duplicate-id | projects/work/duplicate-archive | - | done | - | - | - | - | - |
ARCHIVE

  local name
  for name in active-done blocked-active cycle-a cycle-b cycle-tail malformed \
    archive-ready duplicate-active duplicate-archive; do
    write_tasks "$hub/projects/work/$name" open
    write_empty_plan "$hub/projects/work/$name"
  done
  write_tasks "$hub/projects/work/ready-complete" done
  write_empty_plan "$hub/projects/work/ready-complete"
  write_tasks "$hub/../outside-project" open
  write_empty_plan "$hub/../outside-project"
  ln -s "$hub/../outside-project" "$hub/projects/work/escape"
  mkdir -p "$hub/projects/work/file-escape"
  ln -s "$hub/../outside-project/tasks.md" \
    "$hub/projects/work/file-escape/tasks.md"
  write_empty_plan "$hub/projects/work/file-escape"
  write_tasks "$hub/projects/work/open-done" done
  write_empty_plan "$hub/projects/work/open-done"
  cat >> "$hub/projects/work/open-done/tasks.md" <<'REVISION'

### R7 - regression [OPEN]
- Gap: still broken
- [ ] implement and re-verify

### R8 - title mentions [open] but terminal state is [done]
- archived -> journal
REVISION
  mkdir -p "$hub/projects/work/missing-tasks"
  write_empty_plan "$hub/projects/work/missing-tasks"

  cat > "$hub/projects/work/cycle-a/plan.md" <<'PLAN'
# Project: Cycle A
## Relationships
| relation | target | reason |
|---|---|---|
| depends-on | cycle-b | first half |
PLAN
  cat > "$hub/projects/work/cycle-b/plan.md" <<'PLAN'
# Project: Cycle B
## Relationships
| relation | target | reason |
|---|---|---|
| depends-on | cycle-a | second half |
PLAN
  cat > "$hub/projects/work/cycle-tail/plan.md" <<'PLAN'
# Project: Cycle Tail
## Relationships
| relation | target | reason |
|---|---|---|
| depends-on | cycle-a | downstream of the cycle |
PLAN
  cat > "$hub/projects/work/blocked-active/plan.md" <<'PLAN'
# Project: Blocked Active
## Relationships
| relation | target | reason |
|---|---|---|
| depends-on | open-done | archived target still has an open revision |
PLAN
  cat > "$hub/projects/work/malformed/plan.md" <<'PLAN'
# Project: Malformed
## Relationships
| relation | target | reason |
|---|---|---|
| unknown-edge | cycle-a | unknown semantics |
| related-to | Cycle-A | wrong target case |
| supersedes | missing-project | dangling target |
| related-to | malformed | self edge |
| related-to | cycle-b | duplicate one |
| related-to | cycle-b | duplicate two |
PLAN
}

CLEAN="$TMP/clean"
BAD="$TMP/bad"
make_clean_hub "$CLEAN"
make_corrupt_hub "$BAD"

# Comments and fenced examples do not create edges. An archived settled dependency
# permits API work; the legacy planning reference remains non-blocking.
python3 "$GRAPH" frontier "$CLEAN" > "$TMP/frontier.tsv"
assert_contains "$TMP/frontier.tsv" $'READY\tapi\t'
assert_contains "$TMP/frontier.tsv" $'READY\tapi-v2\t'
assert_contains "$TMP/frontier.tsv" $'BLOCKED\tconsumer\t'
assert_contains "$TMP/frontier.tsv" $'PLANNING\tlegacy-context\t'
assert_not_contains "$TMP/frontier.tsv" "missing-comment-target"
assert_not_contains "$TMP/frontier.tsv" "missing-fence-target"

# Global registry failures stay visible and fail closed even when they produce no
# recognized frontier node.
MISSING="$TMP/missing-registry"
mkdir -p "$MISSING"
if python3 "$GRAPH" frontier "$MISSING" > "$TMP/missing-frontier.tsv"; then
  fail "frontier accepted a hub without index.md"
fi
assert_contains "$TMP/missing-frontier.tsv" $'ERROR\tMISSING_REGISTRY\t'

UNKNOWN="$TMP/unknown-status"
cp -R "$CLEAN" "$UNKNOWN"
awk '
  /^\| api \|/ { sub(/\| ready \|/, "| queued |") }
  { print }
' "$UNKNOWN/index.md" > "$UNKNOWN/index.next"
mv "$UNKNOWN/index.next" "$UNKNOWN/index.md"
if python3 "$GRAPH" frontier "$UNKNOWN" > "$TMP/unknown-frontier.tsv"; then
  fail "frontier accepted an active row with an unknown status"
fi
assert_contains "$TMP/unknown-frontier.tsv" $'ERROR\tUNKNOWN_STATUS\tapi\t'

# An invalid context edge blocks its source, not its otherwise clean target.
CONTEXT_BAD="$TMP/context-bad"
cp -R "$CLEAN" "$CONTEXT_BAD"
printf '| related-to | api | |\n' \
  >> "$CONTEXT_BAD/projects/work/api-v2/plan.md"
if python3 "$GRAPH" frontier "$CONTEXT_BAD" > "$TMP/context-frontier.tsv"; then
  fail "frontier accepted the malformed context edge"
fi
assert_contains "$TMP/context-frontier.tsv" $'READY\tapi\t'
assert_contains "$TMP/context-frontier.tsv" $'BLOCKED\tapi-v2\t'
assert_not_contains "$TMP/context-frontier.tsv" $'BLOCKED\tapi\t'
python3 "$GRAPH" context "$CONTEXT_BAD" api > "$TMP/incoming-context.tsv"
assert_contains "$TMP/incoming-context.tsv" $'NODE\tapi\t'
assert_contains "$TMP/incoming-context.tsv" "runnable=true"
assert_contains "$TMP/incoming-context.tsv" $'IN\trelated-to\tapi-v2\torigin=canonical\tvalid=false\terrors=MISSING_REASON'
assert_not_contains "$TMP/incoming-context.tsv" $'ERROR\tMISSING_REASON\t'
if python3 "$GRAPH" context "$CONTEXT_BAD" api-v2 \
  > "$TMP/owned-context.tsv"; then
  fail "context accepted its own malformed context edge"
fi
assert_contains "$TMP/owned-context.tsv" $'ERROR\tMISSING_REASON\tapi-v2\tapi\t'

# A malformed context edge owned only by an archived project stays out of the active
# scheduling frontier, even when it points at an active project.
COLD_CONTEXT="$TMP/cold-context"
cp -R "$CLEAN" "$COLD_CONTEXT"
printf '| observer | projects/work/observer | - | done | - | - | - | - | - |\n' \
  >> "$COLD_CONTEXT/archive.md"
write_tasks "$COLD_CONTEXT/projects/work/observer" done
cat > "$COLD_CONTEXT/projects/work/observer/plan.md" <<'PLAN'
# Project: Observer

## Relationships

| relation | target | reason |
|---|---|---|
| related-to | api | |
PLAN
python3 "$GRAPH" frontier "$COLD_CONTEXT" > "$TMP/cold-frontier.tsv"
assert_contains "$TMP/cold-frontier.tsv" $'READY\tapi\t'
assert_not_contains "$TMP/cold-frontier.tsv" "MISSING_REASON"
python3 "$GRAPH" why "$COLD_CONTEXT" api > "$TMP/cold-why.tsv"
assert_contains "$TMP/cold-why.tsv" $'RUNNABLE\tapi\t'
assert_not_contains "$TMP/cold-why.tsv" "MISSING_REASON"

# A hard dependency is not trustworthy merely because its task evidence is done:
# source-owned graph errors propagate through depends-on.
BROKEN_PREREQUISITE="$TMP/broken-prerequisite"
cp -R "$CLEAN" "$BROKEN_PREREQUISITE"
cat > "$BROKEN_PREREQUISITE/projects/work/foundation/plan.md" <<'PLAN'
# Project: Foundation

## Relationships

| relation | target | reason |
|---|---|---|
| depends-on | missing-foundation | unresolved prerequisite |
PLAN
if python3 "$GRAPH" frontier "$BROKEN_PREREQUISITE" \
  > "$TMP/broken-prerequisite-frontier.tsv"; then
  fail "frontier accepted a settled dependency with an invalid hard edge"
fi
assert_contains "$TMP/broken-prerequisite-frontier.tsv" $'BLOCKED\tapi\t'
assert_contains "$TMP/broken-prerequisite-frontier.tsv" "foundation(done;open=0;revisions=0;errors=MISSING_TARGET)"
if python3 "$GRAPH" why "$BROKEN_PREREQUISITE" api \
  > "$TMP/broken-prerequisite-why.tsv"; then
  fail "why accepted a settled dependency with an invalid hard edge"
fi
assert_contains "$TMP/broken-prerequisite-why.tsv" $'CHAIN\tapi\thops=1\tapi -> foundation\t'
assert_contains "$TMP/broken-prerequisite-why.tsv" $'ERROR\tMISSING_TARGET\tfoundation\tmissing-foundation\t'
if python3 "$GRAPH" impact "$BROKEN_PREREQUISITE" foundation \
  > "$TMP/broken-prerequisite-impact.tsv"; then
  fail "impact accepted a task-complete source with an invalid hard edge"
fi
assert_not_contains "$TMP/broken-prerequisite-impact.tsv" $'ALREADY_SETTLED\tfoundation\t'
assert_contains "$TMP/broken-prerequisite-impact.tsv" $'AFFECTS\tapi\t'
assert_contains "$TMP/broken-prerequisite-impact.tsv" $'ERROR\tMISSING_TARGET\tfoundation\tmissing-foundation\t'

# Exact names stay exact: api context includes consumer, api-v2 context does not.
python3 "$GRAPH" context "$CLEAN" api > "$TMP/api-context.tsv"
python3 "$GRAPH" context "$CLEAN" api-v2 > "$TMP/api-v2-context.tsv"
assert_contains "$TMP/api-context.tsv" $'IN\tdepends-on\tconsumer\t'
assert_not_contains "$TMP/api-v2-context.tsv" $'\tconsumer\t'
awk -F '\t' '
  {
    for (field = 1; field <= NF; field++) {
      if (length($field) > 240) exit 1
    }
  }
' "$TMP/api-v2-context.tsv" ||
  fail "bounded context emitted a field longer than 240 characters"

# Paths run from prerequisite to dependent over the derived blocks direction.
python3 "$GRAPH" path "$CLEAN" api consumer > "$TMP/path.tsv"
assert_contains "$TMP/path.tsv" $'PATH\tapi\tconsumer\thops=1'
if python3 "$GRAPH" path "$CLEAN" api-v2 consumer > "$TMP/no-path.tsv"; then
  fail "api-v2 unexpectedly has a dependency path to consumer"
fi
assert_contains "$TMP/no-path.tsv" $'NO_PATH\tapi-v2\tconsumer'

# Why reports the shortest unsettled chain; impact walks the derived reverse direction
# with immediate dependents before transitive ones.
python3 "$GRAPH" why "$CLEAN" consumer > "$TMP/why.tsv"
assert_contains "$TMP/why.tsv" $'BLOCKED\tconsumer\tready\tapi(ready;open=1;revisions=0)'
assert_contains "$TMP/why.tsv" $'CHAIN\tconsumer\thops=1\tconsumer -> api\t'
python3 "$GRAPH" impact "$CLEAN" foundation > "$TMP/impact.tsv"
assert_contains "$TMP/impact.tsv" $'ALREADY_SETTLED\tfoundation\tdone\tarchive.md:7'
assert_contains "$TMP/impact.tsv" $'DEPENDENT\tapi\tdistance=1\tfoundation -> api\t'
assert_contains "$TMP/impact.tsv" $'DEPENDENT\tplanning-dependent\tdistance=1\tfoundation -> planning-dependent\t'
assert_contains "$TMP/impact.tsv" $'AFFECTS\tconsumer\tdistance=2\tfoundation -> api -> consumer\t'
python3 "$GRAPH" impact "$CLEAN" api > "$TMP/impact-open.tsv"
assert_contains "$TMP/impact-open.tsv" $'UNLOCKS\tconsumer\tdistance=1\tapi -> consumer\t'

# Link validation is read-only, idempotent for an existing canonical edge, and refuses
# a new dependency cycle without changing a byte in the hub.
python3 "$GRAPH" can-link "$CLEAN" api depends-on foundation > "$TMP/exists.tsv"
assert_contains "$TMP/exists.tsv" $'EXISTS\tapi\tdepends-on\tfoundation'
python3 "$GRAPH" can-link "$CLEAN" api related-to legacy-context > "$TMP/allow.tsv"
assert_contains "$TMP/allow.tsv" $'OK\tapi\trelated-to\tlegacy-context'
before="$(snapshot "$CLEAN")"
if python3 "$GRAPH" can-link "$CLEAN" api depends-on consumer > "$TMP/refused.tsv"; then
  fail "cycle-producing edge was accepted"
fi
after="$(snapshot "$CLEAN")"
[ "$before" = "$after" ] || fail "can-link mutated the hub"
assert_contains "$TMP/refused.tsv" $'ERROR\tWOULD_CREATE_CYCLE\tapi\tconsumer'
if python3 "$GRAPH" can-link "$BAD" cycle-a depends-on cycle-b \
  > "$TMP/existing-cycle.tsv"; then
  fail "existing edge inside an invalid cycle was accepted as clean"
fi
assert_contains "$TMP/existing-cycle.tsv" $'ERROR\tGRAPH_INVALID\tcycle-a\tcycle-b'

# Explicit export is deterministic and JSON carries the versioned schema.
python3 "$GRAPH" export "$CLEAN" tsv > "$TMP/export-1.tsv"
python3 "$GRAPH" export "$CLEAN" tsv > "$TMP/export-2.tsv"
cmp "$TMP/export-1.tsv" "$TMP/export-2.tsv" >/dev/null ||
  fail "TSV export is not deterministic"
awk -F '\t' '
  $1 == "EDGE" && $2 == "api-v2" && $3 == "related-to" {
    found = 1
    if (length($7) < 600) exit 1
  }
  END { if (!found) exit 1 }
' "$TMP/export-1.tsv" ||
  fail "explicit TSV export truncated a canonical reason"
python3 "$GRAPH" export "$CLEAN" json > "$TMP/export.json"
python3 -m json.tool "$TMP/export.json" >/dev/null
assert_contains "$TMP/export.json" '"schema_version": 1'

# Audit detects every fail-closed class and reports exact cycle membership: cycle-a and
# cycle-b are members; cycle-tail merely depends on the cycle.
if python3 "$GRAPH" audit "$BAD" > "$TMP/audit-1.tsv"; then
  fail "corrupt graph audit unexpectedly succeeded"
fi
if python3 "$GRAPH" audit "$BAD" > "$TMP/audit-2.tsv"; then
  fail "second corrupt graph audit unexpectedly succeeded"
fi
cmp "$TMP/audit-1.tsv" "$TMP/audit-2.tsv" >/dev/null ||
  fail "audit output is not deterministic"

for code in DUPLICATE_IDENTITY ACTIVE_DONE ARCHIVE_NON_DONE DONE_OPEN_WORK \
  DONE_MISSING_TASKS UNKNOWN_RELATION TARGET_CASE_MISMATCH MISSING_TARGET \
  SELF_EDGE DUPLICATE_CANONICAL_EDGE DEPENDENCY_CYCLE READY_NO_OPEN_WORK \
  INVALID_PROJECT_PATH; do
  assert_contains "$TMP/audit-1.tsv" "$code"
done
assert_contains "$TMP/audit-1.tsv" $'WARNING\tACTIVE_DONE\tactive-done\t'
assert_not_contains "$TMP/audit-1.tsv" $'ERROR\tACTIVE_DONE\tactive-done\t'
assert_contains "$TMP/audit-1.tsv" $'ERROR\tINVALID_PROJECT_PATH\tescape\t'
assert_contains "$TMP/audit-1.tsv" $'ERROR\tINVALID_PROJECT_PATH\tfile-escape\t'
assert_contains "$TMP/audit-1.tsv" $'ERROR\tDEPENDENCY_CYCLE\tcycle-a\t-\tprojects/work/cycle-a/plan.md:5\t'
assert_contains "$TMP/audit-1.tsv" $'ERROR\tDEPENDENCY_CYCLE\tcycle-b\t-\tprojects/work/cycle-b/plan.md:5\t'
if grep -F $'ERROR\tDEPENDENCY_CYCLE\tcycle-tail\t' "$TMP/audit-1.tsv" >/dev/null; then
  fail "cycle-tail was incorrectly reported as a cycle member"
fi

# An archived done project with an open Revision is not settled and blocks dependents.
if python3 "$GRAPH" context "$BAD" blocked-active > "$TMP/blocked.tsv"; then
  fail "context with dishonest dependency state unexpectedly succeeded"
fi
assert_contains "$TMP/blocked.tsv" "open-done(done;open=1;revisions=1;errors=DONE_OPEN_WORK)"

# A 100-project / 300-edge graph with large cold task histories stays deterministic and
# keeps the default frontier under four kilobytes. Explicit path output remains capped.
SCALE="$TMP/scale"
mkdir -p "$SCALE/projects/work"
cat > "$SCALE/index.md" <<'INDEX'
# Project Index

## Work

| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |
|---|---|---|---|---|---|---|---|---|
INDEX
cat > "$SCALE/archive.md" <<'ARCHIVE'
# Project Archive

## Work

| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |
|---|---|---|---|---|---|---|---|---|
| p000 | projects/work/p000 | - | done | - | - | - | - | - |
ARCHIVE
write_tasks "$SCALE/projects/work/p000" done
write_empty_plan "$SCALE/projects/work/p000"

i=1
while [ "$i" -le 100 ]; do
  name="$(printf 'p%03d' "$i")"
  prior="$(printf 'p%03d' "$((i - 1))")"
  related_index="$((i - 2))"
  superseded_index="$((i - 3))"
  [ "$related_index" -ge 0 ] || related_index=0
  [ "$superseded_index" -ge 0 ] || superseded_index=0
  related="$(printf 'p%03d' "$related_index")"
  superseded="$(printf 'p%03d' "$superseded_index")"

  printf '| %s | projects/work/%s | - | ready | - | - | - | - | - |\n' \
    "$name" "$name" >> "$SCALE/index.md"
  write_tasks "$SCALE/projects/work/$name" open
  {
    printf '\n<!-- '
    awk 'BEGIN { for (i = 0; i < 8192; i++) printf "x" }'
    printf ' -->\n'
  } >> "$SCALE/projects/work/$name/tasks.md"
  cat > "$SCALE/projects/work/$name/plan.md" <<PLAN
# Project: $name

## Goal
Exercise a large deterministic graph.

## Relationships

| relation | target | reason |
|---|---|---|
| depends-on | \`$prior\` | ordered foundation |
| related-to | \`$related\` | context only |
| supersedes | \`$superseded\` | lineage only |
PLAN
  i="$((i + 1))"
done

python3 "$GRAPH" frontier "$SCALE" > "$TMP/scale-frontier-1.tsv"
python3 "$GRAPH" frontier "$SCALE" > "$TMP/scale-frontier-2.tsv"
cmp "$TMP/scale-frontier-1.tsv" "$TMP/scale-frontier-2.tsv" >/dev/null ||
  fail "large frontier output is not deterministic"
assert_contains "$TMP/scale-frontier-1.tsv" "canonical_edges=300"
assert_contains "$TMP/scale-frontier-1.tsv" $'READY\tp001\t'
assert_contains "$TMP/scale-frontier-1.tsv" $'TRUNCATED\tblocked\t79'
frontier_bytes="$(wc -c < "$TMP/scale-frontier-1.tsv" | tr -d '[:space:]')"
[ "$frontier_bytes" -lt 4096 ] ||
  fail "large frontier exceeded 4096 bytes: $frontier_bytes"

python3 "$GRAPH" path "$SCALE" p000 p100 > "$TMP/scale-path.tsv"
assert_contains "$TMP/scale-path.tsv" $'PATH\tp000\tp100\thops=100'
assert_contains "$TMP/scale-path.tsv" $'TRUNCATED\tpath_steps\t81'

scale_corpus_bytes="$(
  find "$SCALE/projects" -type f \( -name plan.md -o -name tasks.md \) \
    -exec wc -c {} + | awk 'END { print $1 }'
)"
[ "$scale_corpus_bytes" -gt 800000 ] ||
  fail "large fixture did not exercise enough cold context: $scale_corpus_bytes"

# A dependency chain above Python's recursion limit compiles without recursive
# traversal and still returns a bounded path.
DEEP="$TMP/deep"
python3 - "$DEEP" <<'PY'
from pathlib import Path
import sys

hub = Path(sys.argv[1])
(hub / "projects/work").mkdir(parents=True)
header = """# Project Index

## Work

| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |
|---|---|---|---|---|---|---|---|---|
"""
active_rows = []
archive_rows = [
    "| d0000 | projects/work/d0000 | - | done | - | - | - | - | - |"
]
for index in range(1101):
    name = f"d{index:04d}"
    project = hub / "projects/work" / name
    project.mkdir()
    done = index == 0
    checkbox = "x" if done else " "
    (project / "tasks.md").write_text(
        f"# Tasks\n\n## Tasks\n- [{checkbox}] complete\n\n## Revisions\n",
        encoding="utf-8",
    )
    if done:
        plan = "# Project\n\n## Goal\nSettled root.\n"
    else:
        prior = f"d{index - 1:04d}"
        plan = (
            "# Project\n\n## Relationships\n\n"
            "| relation | target | reason |\n"
            "|---|---|---|\n"
            f"| depends-on | {prior} | deep chain |\n"
        )
        active_rows.append(
            f"| {name} | projects/work/{name} | - | ready | - | - | - | - | - |"
        )
    (project / "plan.md").write_text(plan, encoding="utf-8")

(hub / "index.md").write_text(
    header + "\n".join(active_rows) + "\n", encoding="utf-8"
)
(hub / "archive.md").write_text(
    header.replace("# Project Index", "# Project Archive")
    + "\n".join(archive_rows)
    + "\n",
    encoding="utf-8",
)
PY
python3 "$GRAPH" frontier "$DEEP" > "$TMP/deep-frontier.tsv"
assert_contains "$TMP/deep-frontier.tsv" "nodes=1101"
python3 "$GRAPH" path "$DEEP" d0000 d1100 > "$TMP/deep-path.tsv"
assert_contains "$TMP/deep-path.tsv" $'PATH\td0000\td1100\thops=1100'
assert_contains "$TMP/deep-path.tsv" $'TRUNCATED\tpath_steps\t1081'

# A layered Directed Acyclic Graph has exponentially many raw paths. Why keeps one
# deterministic shortest path per terminal instead of materializing them all.
LAYERED="$TMP/layered"
python3 - "$LAYERED" <<'PY'
from pathlib import Path
import sys

hub = Path(sys.argv[1])
(hub / "projects/work").mkdir(parents=True)
names = ["root"] + [
    f"l{layer:02d}{branch}"
    for layer in range(1, 15)
    for branch in ("a", "b")
]
header = """# Project Index

## Work

| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |
|---|---|---|---|---|---|---|---|---|
"""
rows = []
for name in names:
    project = hub / "projects/work" / name
    project.mkdir()
    rows.append(
        f"| {name} | projects/work/{name} | - | ready | - | - | - | - | - |"
    )
    (project / "tasks.md").write_text(
        "# Tasks\n\n## Tasks\n- [ ] complete\n\n## Revisions\n",
        encoding="utf-8",
    )
    if name == "root":
        targets = ("l01a", "l01b")
    elif name.startswith("l14"):
        targets = ()
    else:
        layer = int(name[1:3]) + 1
        targets = (f"l{layer:02d}a", f"l{layer:02d}b")
    relationship_rows = "".join(
        f"| depends-on | {target} | layered dependency |\n" for target in targets
    )
    plan = "# Project\n"
    if targets:
        plan += (
            "\n## Relationships\n\n"
            "| relation | target | reason |\n"
            "|---|---|---|\n"
            + relationship_rows
        )
    (project / "plan.md").write_text(plan, encoding="utf-8")

(hub / "index.md").write_text(header + "\n".join(rows) + "\n", encoding="utf-8")
(hub / "archive.md").write_text(
    header.replace("# Project Index", "# Project Archive"), encoding="utf-8"
)
PY
python3 "$GRAPH" why "$LAYERED" root > "$TMP/layered-why.tsv"
assert_contains "$TMP/layered-why.tsv" "chains=2"
chain_count="$(grep -c '^CHAIN' "$TMP/layered-why.tsv")"
[ "$chain_count" -eq 2 ] ||
  fail "layered why emitted $chain_count chains instead of one per terminal"

printf 'graph contract: ok\n'
