#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
report="$repo_root/skills/todo-archive/scripts/archive-report.sh"
hook="$repo_root/hooks/archive-candidates.sh"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

expect_equal() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" != "$expected" ]; then
    printf 'not ok - %s\nexpected: %s\nactual:   %s\n' \
      "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

expect_contains() {
  local file="$1"
  local text="$2"
  grep -Fq "$text" "$file" ||
    fail "$file must contain: $text"
}

expect_matches() {
  local file="$1"
  local pattern="$2"
  grep -Eq "$pattern" "$file" ||
    fail "$file must match: $pattern"
}

file_mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null
}

write_lines() {
  local path="$1"
  shift
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$@" > "$path"
}

[ -f "$report" ] || fail "archive report helper is missing"
[ -f "$hook" ] || fail "archive candidate hook is missing"

fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

candidate_hub="$fixture_root/candidates"
write_lines "$candidate_hub/index.md" \
  '# Project Index' \
  '' \
  '## Work' \
  '' \
  '| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |' \
  '|---|---|---|---|---|---|---|---|---|' \
  '| alpha | projects/work/alpha | - | DONE | - | - | - | - | - |' \
  '| beta | projects/work/beta | - | in-progress | - | - | - | - | - |' \
  '| gamma | projects/work/gamma | - | in-progress | - | - | - | - | - |' \
  '| delta | projects/work/delta | - | in-progress | - | - | - | - | - |' \
  '| dupe | projects/work/dupe | - | in-progress | - | - | - | - | - |' \
  '| blocked | projects/work/blocked | - | done | - | - | - | - | - |' \
  '| backtick | `projects/work/backtick` | - | done | - | - | - | - | - |' \
  '' \
  '## Archive' \
  '' \
  '| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |' \
  '|---|---|---|---|---|---|---|---|---|' \
  '| legacy-open | projects/work/legacy-open | - | done | - | - | - | - | - |'

write_lines "$candidate_hub/archive.md" \
  '# Project Archive' \
  '' \
  '## Work' \
  '' \
  '| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |' \
  '|---|---|---|---|---|---|---|---|---|' \
  '| cold | projects/work/cold | - | done | - | - | - | - | - |' \
  '| cold-open | projects/work/cold-open | - | done | - | - | - | - | - |' \
  '| cold-ready | projects/work/cold-ready | - | ready | - | - | - | - | - |' \
  '| dupe | projects/work/dupe | - | done | - | - | - | - | - |'

write_lines "$candidate_hub/projects/work/beta/tasks.md" \
  '# Tasks' \
  '' \
  '## Revisions' \
  '' \
  '### R1 — lowercase done [done]' \
  '- Gap: lowercase' \
  '' \
  '### R2 — uppercase done [DONE]' \
  '- Gap: uppercase' \
  '' \
  '### R3 — annotated done [Done — shipped]' \
  '- Gap: annotated' \
  '' \
  '### R4 — linked tombstone [done]' \
  '- archived → [journal:R4](artifacts/journal.md#revision-r4) (2026-07-26)' \
  '' \
  '### R5 — still open [open]' \
  '- Gap: must stay live' \
  '' \
  '### R6 — repairable legacy tombstone [done]' \
  '- archived → artifacts/journal.md (2026-07-26)' \
  '' \
  '### R7 — broken linked tombstone [done]' \
  '- archived → [journal:R7](artifacts/journal.md#revision-r7) (2026-07-26)' \
  '' \
  '### R8 — wrong direct target [done]' \
  '- archived → [journal:R4](artifacts/journal.md#revision-r4) (2026-07-26)' \
  '' \
  '### R9 — title mentions [done] but terminal state is [OPEN]' \
  '- Gap: this remains open' \
  '' \
  '### R13 — visible detail with inline comment [done]' \
  '- Gap: visible <!-- hidden note -->' \
  '```markdown' \
  '### R14 — fenced example [done]' \
  '- Gap: must not count separately' \
  '```' \
  '' \
  '### R10 — empty completed entry [done]' \
  '' \
  '## Notes' \
  '' \
  '### R11 — not inside Revisions [done]' \
  '- Gap: must not count' \
  '<!--' \
  '### R12 — commented template [done]' \
  '- Gap: must not count' \
  '-->'

write_lines "$candidate_hub/projects/work/beta/artifacts/journal.md" \
  '# Journal' \
  '' \
  '<a id="revision-r4"></a>' \
  '## R4 — linked target' \
  '- linked detail' \
  '' \
  '### R6 — unique legacy target' \
  '- legacy detail' \
  '' \
  '<a id="revision-r8"></a>' \
  '## R8 — correct target' \
  '- correct detail'

write_lines "$candidate_hub/projects/work/blocked/tasks.md" \
  '# Tasks' \
  '' \
  '## Revisions' \
  '' \
  '### R1 — open revision [OPEN]' \
  '- Gap: blocks retirement'

write_lines "$candidate_hub/projects/work/cold-open/tasks.md" \
  '# Tasks' \
  '' \
  '## Revisions' \
  '' \
  '### R72b — archived row is stale [Open — follow-up]' \
  '- Gap: archived project must reactivate'

write_lines "$candidate_hub/projects/work/backtick/tasks.md" \
  '# Tasks' \
  '' \
  '## Revisions' \
  '' \
  '### R1 — backticked path still resolves [open]' \
  '- Gap: blocks retirement'

write_lines "$candidate_hub/projects/work/legacy-open/tasks.md" \
  '# Tasks' \
  '' \
  '## Revisions' \
  '' \
  '### R1 — legacy row must reactivate [open]' \
  '- Gap: blocks cold migration'

for project in alpha cold cold-ready dupe; do
  write_lines "$candidate_hub/projects/work/$project/tasks.md" \
    '# Tasks' \
    '' \
    '## Tasks' \
    '- [x] complete'
done

mkdir -p \
  "$candidate_hub/projects/work/gamma" \
  "$candidate_hub/projects/work/delta"
awk 'BEGIN { for (i = 0; i < 20481; i++) printf "x" }' \
  > "$candidate_hub/projects/work/gamma/tasks.md"
awk 'BEGIN { for (i = 0; i < 20480; i++) printf "x" }' \
  > "$candidate_hub/projects/work/delta/tasks.md"

candidate_output="$(
  PLUGIN_ROOT="$repo_root" TODO_HUB="$candidate_hub" bash "$hook"
)"
expect_equal \
  "candidate hook reports exact bounded summary" \
  'todo-list: archive candidates — detailed_done_revisions=4; tombstone_link_repairs=2; broken_tombstones=1; done_index_rows=1; state_conflicts=5; registry_duplicates=1; oversized_tasks=1; projects=alpha,backtick,beta,blocked,cold-open,cold-ready,dupe,gamma,+1 more. Run /todo-archive to review.' \
  "$candidate_output"
printf 'ok - case-insensitive candidates, pointers, threshold, and registries\n'

registry_output_file="$fixture_root/registry-audit.tsv"
bash "$report" audit "$candidate_hub" registry > "$registry_output_file"
expect_contains "$registry_output_file" $'alpha\tactive\tWork'
if grep -q $'^beta\t' "$registry_output_file"; then
  fail "registry-only audit must exclude revision-only candidates"
fi

filtered_output_file="$fixture_root/filtered-audit.tsv"
bash "$report" audit "$candidate_hub" beta > "$filtered_output_file"
expect_contains "$filtered_output_file" 'duplicate_names=0'
printf 'ok - registry-only and filtered audits stay scoped\n'

preview_hub="$fixture_root/preview"
write_lines "$preview_hub/index.md" \
  '# Project Index' \
  '' \
  '## Work' \
  '' \
  '| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |' \
  '|---|---|---|---|---|---|---|---|---|'
for number in 01 02 03 04 05 06 07 08 09 10; do
  printf '| p%s | projects/work/p%s | - | done | - | - | - | - | - |\n' \
    "$number" "$number" >> "$preview_hub/index.md"
  write_lines "$preview_hub/projects/work/p$number/tasks.md" \
    '# Tasks' \
    '' \
    '## Tasks' \
    '- [x] complete'
done

preview_output="$(
  PLUGIN_ROOT="$repo_root" TODO_HUB="$preview_hub" bash "$hook"
)"
expect_equal \
  "candidate hook caps its project-name preview" \
  'todo-list: archive candidates — detailed_done_revisions=0; tombstone_link_repairs=0; broken_tombstones=0; done_index_rows=10; state_conflicts=0; registry_duplicates=0; oversized_tasks=0; projects=p01,p02,p03,p04,p05,p06,p07,p08,+2 more. Run /todo-archive to review.' \
  "$preview_output"
printf 'ok - SessionStart project preview is bounded\n'

clean_hub="$fixture_root/clean"
write_lines "$clean_hub/index.md" \
  '# Project Index' \
  '' \
  '## Work' \
  '' \
  '| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |' \
  '|---|---|---|---|---|---|---|---|---|' \
  '| clean | projects/work/clean | - | in-progress | - | - | - | - | - |'
write_lines "$clean_hub/archive.md" \
  '# Project Archive' \
  '' \
  '## Work' \
  '' \
  '| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |' \
  '|---|---|---|---|---|---|---|---|---|' \
  '| cold | projects/work/cold | - | done | - | - | - | - | - |'
write_lines "$clean_hub/projects/work/clean/tasks.md" \
  '# Tasks' \
  '' \
  '## Revisions' \
  '' \
  '### R4 — linked tombstone [done]' \
  '- archived → [journal:R4](artifacts/journal.md#revision-r4) (2026-07-26)'
write_lines "$clean_hub/projects/work/clean/artifacts/journal.md" \
  '# Journal' \
  '' \
  '<a id="revision-r4"></a>' \
  '## R4 — linked target' \
  '- linked detail'
write_lines "$clean_hub/projects/work/cold/tasks.md" \
  '# Tasks' \
  '' \
  '## Tasks' \
  '- [x] complete'

clean_output="$(
  PLUGIN_ROOT="$repo_root" TODO_HUB="$clean_hub" bash "$hook"
)"
expect_equal "clean hook is silent" "" "$clean_output"

missing_output="$(
  PLUGIN_ROOT="$repo_root" TODO_HUB="$fixture_root/missing" bash "$hook"
)"
expect_equal "missing hub is silent" "" "$missing_output"
seed_output="$(
  PLUGIN_ROOT="$repo_root" TODO_HUB="$repo_root/seed" bash "$hook"
)"
expect_equal "commented seed examples are ignored" "" "$seed_output"
printf 'ok - clean, missing, and commented seed hubs are silent\n'

lookup_hub="$fixture_root/lookup"
write_lines "$lookup_hub/projects/work/history/tasks.md" \
  '# Tasks' \
  '' \
  '## Tasks' \
  '- [ ] visible task <!-- hidden note -->' \
  '```markdown' \
  '- [ ] fenced example' \
  '```' \
  '' \
  '## Notes' \
  '- [ ] informational checkbox' \
  '' \
  '## Revisions' \
  '' \
  '### R7 — live revision [OPEN]' \
  '- Gap: return this task block'
write_lines "$lookup_hub/projects/work/history/artifacts/journal.md" \
  '# Journal' \
  '' \
  '```markdown' \
  '## R1 — fenced fake target' \
  '```' \
  '' \
  '## R10 — must not satisfy R1' \
  '- ten detail' \
  '' \
  '## R1 — level-two exact target' \
  '- one detail' \
  '' \
  '### R2A — level-three suffixed target' \
  '- suffixed detail' \
  '' \
  '<a id="revision-r4"></a>' \
  '### R4 — anchored target' \
  '- anchored detail' \
  '```markdown' \
  '## R400 — fenced heading is detail' \
  '```' \
  '' \
  '<a id="revision-r5"></a>' \
  '## R5 — next target' \
  '- five detail' \
  '' \
  '## R6 — ambiguous first target' \
  '- first detail' \
  '' \
  '### R6 — ambiguous second target' \
  '- second detail' \
  '' \
  '<a id="revision-r8"></a>' \
  '# Aggregate' \
  '### R8 — displaced target' \
  '- must be rejected' \
  '' \
  '<a id="revision-r9"></a>' \
  '### r9 — lowercase anchored target' \
  '- lowercase detail' \
  '' \
  '## R11 — must not leak into R9' \
  '- eleven detail'

context_output="$(
  bash "$report" context "$lookup_hub" projects/work/history
)"
expect_equal \
  "bounded context ignores comments, fences, and Notes" \
  $'TASK\t4\t- [ ] visible task\nREVISION\t14\t### R7 — live revision [OPEN]\nSUMMARY\t0\t1\t1\t1' \
  "$context_output"

r1_output="$(bash "$report" lookup "$lookup_hub" projects/work/history r1)"
expect_equal \
  "R1 lookup does not match R10" \
  $'## R1 — level-two exact target\n- one detail' \
  "$r1_output"

r2a_output="$(bash "$report" lookup "$lookup_hub" projects/work/history R2A)"
expect_equal \
  "level-three suffixed lookup" \
  $'### R2A — level-three suffixed target\n- suffixed detail' \
  "$r2a_output"

r4_output="$(bash "$report" lookup "$lookup_hub" projects/work/history R4)"
expect_equal \
  "anchored lookup stops at the next revision anchor" \
  $'<a id="revision-r4"></a>\n### R4 — anchored target\n- anchored detail\n```markdown\n## R400 — fenced heading is detail\n```' \
  "$r4_output"

r7_output="$(bash "$report" lookup "$lookup_hub" projects/work/history R7)"
expect_equal \
  "live revision lookup reads tasks before journal" \
  $'### R7 — live revision [OPEN]\n- Gap: return this task block' \
  "$r7_output"

if bash "$report" lookup "$lookup_hub" projects/work/history R8 \
  > "$fixture_root/displaced.out" 2> "$fixture_root/displaced.err"; then
  fail "displaced anchor lookup must fail"
fi
expect_contains "$fixture_root/displaced.err" \
  'R8 anchor does not immediately identify its journal heading'

r9_output="$(bash "$report" lookup "$lookup_hub" projects/work/history R9)"
expect_equal \
  "lowercase anchored lookup remains bounded" \
  $'<a id="revision-r9"></a>\n### r9 — lowercase anchored target\n- lowercase detail' \
  "$r9_output"

if bash "$report" lookup "$lookup_hub" projects/work/history R6 \
  > "$fixture_root/ambiguous.out" 2> "$fixture_root/ambiguous.err"; then
  fail "ambiguous legacy lookup must fail"
fi
expect_contains "$fixture_root/ambiguous.err" 'R6 has multiple legacy headings'
printf 'ok - exact bounded revision lookup\n'

session_start_block="$(
  awk '
    /"SessionStart"/ { in_session_start = 1 }
    /"Stop"/ { in_session_start = 0 }
    in_session_start { print }
  ' "$repo_root/hooks/hooks.json"
)"
case "$session_start_block" in
  *'hooks/archive-candidates.sh'*) ;;
  *) fail "archive candidate hook must be registered under SessionStart" ;;
esac

[ -f "$repo_root/seed/archive.md" ] ||
  fail "seed/archive.md must exist"
expect_contains "$repo_root/seed/archive.md" '# Project Archive'
expect_contains "$repo_root/skills/todo-archive/SKILL.md" '$TODO_HUB/archive.md'
expect_contains "$repo_root/skills/todo-refer/SKILL.md" 'archive.md'
expect_contains "$repo_root/skills/todo-list/SKILL.md" 'archive.md'

if grep -Eq '^## Archive$' "$repo_root/seed/index.md"; then
  fail "seed/index.md must remain active-only"
fi

for skill in \
  "$repo_root/skills/todo-archive/SKILL.md" \
  "$repo_root/skills/todo-revise/SKILL.md" \
  "$repo_root/skills/todo-state/SKILL.md"; do
  expect_matches \
    "$skill" \
    'artifacts/journal\.md#revision-r(<n>|[0-9]+[A-Za-z]*)'
done

expect_contains \
  "$repo_root/skills/todo-refer/SKILL.md" \
  'archive-report.sh lookup'
expect_contains \
  "$repo_root/skills/todo-refer/SKILL.md" \
  'R1'
expect_contains \
  "$repo_root/skills/todo-refer/SKILL.md" \
  'R10'
expect_contains \
  "$repo_root/skills/todo-refer/SKILL.md" \
  'revision-only question'
expect_contains \
  "$repo_root/skills/todo-refer/SKILL.md" \
  'bounded context helper'
expect_contains \
  "$repo_root/skills/todo-refer/SKILL.md" \
  'archive-report.sh context'
expect_contains \
  "$repo_root/skills/todo-archive/SKILL.md" \
  'duplicate short-names'
expect_contains \
  "$repo_root/skills/todo-archive/SKILL.md" \
  'state conflicts such as archived'
expect_contains \
  "$repo_root/hooks/superpowers-doc-sync.sh" \
  'for registry in "$INDEX" "$ARCHIVE"'
printf 'ok - hook registration and prompt contracts\n'

fresh_hub="$fixture_root/fresh"
bootstrap_output="$(
  PLUGIN_ROOT="$repo_root" TODO_HUB="$fresh_hub" \
    bash "$repo_root/hooks/bootstrap-hub.sh"
)"
[ -f "$fresh_hub/index.md" ] || fail "fresh bootstrap must seed index.md"
[ -f "$fresh_hub/archive.md" ] || fail "fresh bootstrap must seed archive.md"
[ -f "$fresh_hub/REGISTRY.md" ] || fail "fresh bootstrap must seed REGISTRY.md"
expect_equal \
  "fresh bootstrap names both registries" \
  "todo-list: created your project hub at $fresh_hub (index.md, archive.md, templates, and an example project). It is the default location — set the TODO_HUB env var to move it." \
  "$bootstrap_output"
bootstrap_second_output="$(
  PLUGIN_ROOT="$repo_root" TODO_HUB="$fresh_hub" \
    bash "$repo_root/hooks/bootstrap-hub.sh"
)"
expect_equal "bootstrap is silent after both registries exist" "" "$bootstrap_second_output"

# A hub created before REGISTRY.md existed gets the reference backfilled, once, without
# recopying anything else.
predoc_hub="$fixture_root/predoc"
write_lines "$predoc_hub/index.md" '# Project Index'
write_lines "$predoc_hub/archive.md" '# Project Archive'
predoc_output="$(
  PLUGIN_ROOT="$repo_root" TODO_HUB="$predoc_hub" \
    bash "$repo_root/hooks/bootstrap-hub.sh"
)"
[ -f "$predoc_hub/REGISTRY.md" ] || fail "existing hub must receive REGISTRY.md"
case "$predoc_output" in
  *"$predoc_hub/REGISTRY.md"*) ;;
  *) fail "REGISTRY.md backfill must announce itself" ;;
esac
expect_contains "$predoc_hub/index.md" '# Project Index'
if [ -d "$predoc_hub/templates" ]; then
  fail "backfill must not recopy the rest of the seed"
fi
predoc_second_output="$(
  PLUGIN_ROOT="$repo_root" TODO_HUB="$predoc_hub" \
    bash "$repo_root/hooks/bootstrap-hub.sh"
)"
expect_equal "REGISTRY.md backfill is idempotent" "" "$predoc_second_output"
printf 'ok - registry reference backfill\n'

legacy_hub="$fixture_root/legacy"
write_lines "$legacy_hub/index.md" \
  '# Project Index' \
  '' \
  '## Work' \
  '' \
  '| short-name | path | repo | status | infographic | related |' \
  '|---|---|---|---|---|---|' \
  '| active | projects/work/active | - | in-progress | - | - |'
write_lines "$legacy_hub/archive.md" \
  '# Project Archive' \
  '' \
  '## Work' \
  '' \
  '| short-name | path | repo | status | infographic | related |' \
  '|---|---|---|---|---|---|' \
  '| cold | projects/work/cold | - | DONE | - | - |'
chmod 644 "$legacy_hub/index.md" "$legacy_hub/archive.md"

migration_output="$(
  TODO_HUB="$legacy_hub" bash "$repo_root/hooks/migrate-index-dates.sh"
)"
expect_contains "$legacy_hub/index.md" '| started | completed | elapsed (days) |'
expect_contains "$legacy_hub/archive.md" '| started | completed | elapsed (days) |'
expect_equal "active registry mode is preserved" "644" "$(file_mode "$legacy_hub/index.md")"
expect_equal "archive registry mode is preserved" "644" "$(file_mode "$legacy_hub/archive.md")"
[ -f "$legacy_hub/index.md.pre-dates.bak" ] ||
  fail "active registry migration must create a backup"
[ -f "$legacy_hub/archive.md.pre-dates.bak" ] ||
  fail "archive registry migration must create a backup"
case "$migration_output" in
  *"$legacy_hub/index.md"*"$legacy_hub/archive.md"*) ;;
  *) fail "migration must report both changed registries" ;;
esac
migration_second_output="$(
  TODO_HUB="$legacy_hub" bash "$repo_root/hooks/migrate-index-dates.sh"
)"
expect_equal "registry migration is idempotent" "" "$migration_second_output"
printf 'ok - bootstrap and both-registry migration contracts\n'

docs_hub="$fixture_root/docs-hub"
docs_repo="$fixture_root/repo with space"
write_lines "$docs_hub/index.md" \
  '# Project Index' \
  '' \
  '## Work' \
  '' \
  '| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |' \
  '|---|---|---|---|---|---|---|---|---|'
write_lines "$docs_hub/archive.md" \
  '# Project Archive' \
  '' \
  '## Work' \
  '' \
  '| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |' \
  '|---|---|---|---|---|---|---|---|---|' \
  "| cold-docs | projects/work/cold-docs | $docs_repo | done | - | - | - | - | - |"
write_lines "$docs_repo/docs/superpowers/plans/bad\"name.md" \
  '# Untracked design'
mkdir -p "$docs_hub/projects"

docs_hook_output="$(
  printf '{}\n' |
    TODO_HUB="$docs_hub" bash "$repo_root/hooks/superpowers-doc-sync.sh"
)"
case "$docs_hook_output" in
  *'"decision":"block"'*'bad\"name.md'*) ;;
  *) fail "doc-sync must support archived repo paths with spaces and JSON-escape quotes" ;;
esac
printf 'ok - archived doc-sync paths and JSON escaping\n'

printf 'archive contract tests passed\n'
