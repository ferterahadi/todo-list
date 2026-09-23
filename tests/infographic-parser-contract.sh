#!/usr/bin/env bash
# Parser, legacy-guard, and bounded-patch contract for the infographic refresh helper.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
refresh="$repo_root/skills/todo-infographic/scripts/refresh-infographic.py"
graph="$repo_root/skills/todo-graph/scripts/graph-report.py"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/todo-infographic-parser.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export PYTHONDONTWRITEBYTECODE=1

# expect <label> <manifest> <python expression over the manifest `v`> <expected>
expect() {
  local actual
  actual="$(python3 -c 'import json,sys; v=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$2" "$3")"
  [ "$actual" = "$4" ] || fail "$1: expected $4, got $actual"
}

inspect() {
  python3 "$refresh" inspect "$1" --date 2026-09-23 --status in-progress --output "$2"
}

refused() {
  local label="$1" html="$2"
  shift 2
  cp "$html" "$tmp/before.html"
  if python3 "$refresh" "$@" > "$tmp/refused.out" 2> "$tmp/refused.err"; then
    fail "$label: expected a refusal"
  fi
  cmp -s "$html" "$tmp/before.html" || fail "$label: a refused command changed the page"
}

write_plan() {
  cat > "$1/plan.md" <<'PLAN'
# Project: Parser fixture

## Goal
Old goal sentence.

## Context
The page is refreshed from marked values.

## Relationships
- Depends on: nothing yet.

## Key Decisions
- **D1 — Bullet decisions count.** The plan may use bullets.
- ~~**D2**~~ — superseded decisions keep their card.
PLAN
}

# 1 — the canonical rule: level-3 phases under `## Tasks`, a level-3 subsection in a
# level-2 phase, Revisions checkboxes, and uncounted comment/fence/Notes/preamble lines.
canon="$tmp/canon"
mkdir -p "$canon"
write_plan "$canon"
cat > "$canon/tasks.md" <<'TASKS'
# Tasks
- [x] Before the first level-2 heading: not a task.

## Tasks

### Phase 1 — Parser
- [x] Canonical rule.
- [ ] Level-3 phases.
<!--
- [x] Commented out: not a task.
-->

### Phase 2b — Fixtures
- [X] Upper-case X is done.
```markdown
- [ ] Fenced: not a task.
```
- [ ] Real task after the fence.

## Phase 3 — Level-2 phase
- [x] Level-2 phase task.

### Phase 3 log
- [ ] A subsection of Phase 3, not a new phase.

## Revisions
### Phase 9 follow-up
- [ ] R1 — Revisions checkboxes count.

## Notes
- [x] Notes checkbox: not a task.
TASKS
inspect "$canon" "$tmp/canon.json"
expect "canonical totals" "$tmp/canon.json" 'v["current"]["values"]["task-summary"]' '3 done / 7'
expect "canonical open" "$tmp/canon.json" 'v["current"]["values"]["task-open"]' '4'
expect "canonical phases" "$tmp/canon.json" \
  '" ".join("%s=%s/%s" % (p["key"], p["done"], p["total"]) for p in v["current"]["phases"])' \
  'phase-1=1/2 phase-2b=1/2 phase-3=1/2'
expect "phase count" "$tmp/canon.json" 'v["current"]["values"]["phase-count"]' '3'
expect "bullet decisions" "$tmp/canon.json" 'v["current"]["decision_ids"]' "['D1', 'D2']"
graph_counts="$(python3 - "$graph" "$canon/tasks.md" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("graph_report", sys.argv[1])
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
stats = module.parse_task_stats(__import__("pathlib").Path(sys.argv[2]))
print(f"{stats.done} done / {stats.total}")
PY
)"
[ "$graph_counts" = "3 done / 7" ] || fail "graph-report.py disagrees with the helper: $graph_counts"

# 2 — a flat list is valid and has no phases.
flat="$tmp/flat"
mkdir -p "$flat"
write_plan "$flat"
printf '# Tasks\n\n## Tasks\n- [x] One.\n- [ ] Two.\n- [ ] Three.\n' > "$flat/tasks.md"
inspect "$flat" "$tmp/flat.json"
expect "flat phases" "$tmp/flat.json" 'v["current"]["values"]["phase-count"]' '0'
expect "flat totals" "$tmp/flat.json" 'v["current"]["values"]["task-summary"]' '1 done / 3'

# 3 — a decimal phase is its own phase; a repeated phase number fails closed.
decimal="$tmp/decimal"
mkdir -p "$decimal"
write_plan "$decimal"
printf '# Tasks\n\n## Phase 4 — A\n- [x] a\n\n## Phase 4.5 — B\n- [ ] b\n- [ ] c\n' > "$decimal/tasks.md"
inspect "$decimal" "$tmp/decimal.json"
expect "decimal phases" "$tmp/decimal.json" 'v["current"]["values"]["phase-count"]' '2'
expect "decimal phase key" "$tmp/decimal.json" '[(p["key"], p["done"], p["total"]) for p in v["current"]["phases"]][1]' "('phase-4.5', 0, 2)"

dup="$tmp/dup"
mkdir -p "$dup"
write_plan "$dup"
printf '# Tasks\n\n## Phase 4 — A\n- [ ] a\n\n## Phase 4 — B\n- [ ] b\n' > "$dup/tasks.md"
if inspect "$dup" "$tmp/dup.json" 2> "$tmp/dup.err"; then
  fail "duplicate phase numbers were accepted"
fi
grep -Fq 'share a phase number' "$tmp/dup.err" || fail "duplicate phase error is unclear"

# 4 — stub plans are reported by inspect, and apply refuses them.
stub="$tmp/stub"
mkdir -p "$stub/artifacts"
printf '# Project: stub\n\n## Goal\nWhat success looks like in one sentence.\n\n## Scope\n**In:** what'"'"'s included\n**Out:** what'"'"'s excluded\n' \
  > "$stub/plan.md"
printf '# Tasks\n\n## Tasks\n- [ ] a\n' > "$stub/tasks.md"
printf '<html><body></body></html>\n' > "$stub/artifacts/infographic.html"
inspect "$stub" "$tmp/stub.json"
expect "stub mode" "$tmp/stub.json" 'v["mode"]' 'stub'
expect "stub reasons" "$tmp/stub.json" 'v["reasons"]' "['stub-template-goal', 'stub-template-scope']"
refused "stub apply" "$stub/artifacts/infographic.html" apply "$stub" --date 2026-09-23 --status ready
printf '# Project: no goal\n\n## Context\nSomething.\n' > "$stub/plan.md"
inspect "$stub" "$tmp/stub-missing.json"
expect "missing goal" "$tmp/stub-missing.json" 'v["reasons"]' "['stub-missing-goal']"

# 5 — a legacy page for level-3 phases migrates with canonical counts (the
# quorum-queue regression: level-3 phases used to parse as zero phases).
legacy_page() {
  cat <<HTML
<title>Parser fixture</title>
<style>.bar{height:4px}.n{font-size:2rem}</style>
<h2 class="goal">Old goal sentence.</h2>
<section class="stats">
  <div class="stat"><span class="n">$1</span><span class="k">Phases</span></div>
  <div class="stat"><span class="n">1/3</span><span class="k">Tasks done</span></div>
</section>
<section class="decisions">
  <div class="card"><span>[D1]</span><p>Bullet decisions count.</p><span>Gain</span><span>Cost</span></div>
  <div class="card"><span>[D2]</span><p>Superseded.</p><span>Gain</span><span>Cost</span></div>
</section>
HTML
  shift
  for block in "$@"; do
    printf '<section class="phase"><span>Phase %s</span><span>%s</span><div class="bar" style="width:0%%"></div><ul><li>Task summary 3/3 green</li></ul></section>\n' \
      "${block%%=*}" "${block#*=}"
  done
  printf '<footer><span>Generated from plan.md + tasks.md · 2026-09-01</span></footer>\n'
}
legacy="$tmp/legacy"
mkdir -p "$legacy/artifacts"
write_plan "$legacy"
cat > "$legacy/tasks.md" <<'TASKS'
# Tasks

## Tasks

### Phase 1 — Parser
- [x] Canonical rule.
- [ ] Level-3 phases.

### Phase 2 — Fixtures
- [ ] Legacy page.
TASKS
html="$legacy/artifacts/infographic.html"
# The page omits the optional html/body tags and leaves nothing open: accepted.
legacy_page '0/2' '1=0/2' '2=0/1' > "$html"
inspect "$legacy" "$tmp/legacy.json"
expect "legacy mode" "$tmp/legacy.json" 'v["mode"]' 'legacy-migration'
python3 "$refresh" migrate "$legacy" --date 2026-09-23 --status in-progress \
  --manifest "$tmp/legacy.json" --confirm-content-current > /dev/null
python3 "$refresh" verify "$legacy" > /dev/null
grep -Fq '<span data-todo-value="phase-done">0</span>/<span data-todo-value="phase-count">2</span>' "$html" ||
  fail "legacy phase ratio was not bound as phase-done/phase-count"
grep -Fq '<span data-todo-value="task-done">1</span>/<span data-todo-value="task-total">3</span>' "$html" ||
  fail "legacy task ratio does not show the canonical 1/3"
grep -Fq 'data-todo-phase-count="phase-1">1/2<' "$html" || fail "phase-1 count is not canonical"
grep -Fq 'data-todo-phase-count="phase-2">0/1<' "$html" || fail "phase-2 count is not canonical"
grep -Fq 'Task summary 3/3 green' "$html" || fail "task-row prose was altered"

# 5b — ticking the last Phase 1 task is a fast refresh that moves phase-done.
sed -i.bak 's/- \[ \] Level-3 phases\./- [x] Level-3 phases./' "$legacy/tasks.md"
rm "$legacy/tasks.md.bak"
inspect "$legacy" "$tmp/legacy-fast.json"
expect "phase-done fast refresh" "$tmp/legacy-fast.json" 'v["mode"]' 'fast-refresh'
python3 "$refresh" apply "$legacy" --date 2026-09-23 --status in-progress > /dev/null
python3 "$refresh" verify "$legacy" > /dev/null
grep -Fq '<span data-todo-value="phase-done">1</span>' "$html" || fail "phase-done did not update"

# 5c — a change only in an unrendered plan section is a fast refresh.
sed -i.bak 's/Depends on: nothing yet\./Depends on: another project./' "$legacy/plan.md"
rm "$legacy/plan.md.bak"
inspect "$legacy" "$tmp/legacy-hidden.json"
expect "hidden section mode" "$tmp/legacy-hidden.json" 'v["mode"]' 'fast-refresh'
expect "hidden section reason" "$tmp/legacy-hidden.json" \
  '"unrendered-plan-sections-changed" in v["reasons"]' 'True'
python3 "$refresh" apply "$legacy" --date 2026-09-23 --status in-progress > /dev/null

# 6 — a page whose phase structure differs from tasks.md is refused, never guessed.
mismatch="$tmp/mismatch"
mkdir -p "$mismatch/artifacts"
write_plan "$mismatch"
cp "$tmp/legacy/tasks.md" "$mismatch/tasks.md"
legacy_page '3' '1=0/2' '2=0/1' '3=0/4' > "$mismatch/artifacts/infographic.html"
inspect "$mismatch" "$tmp/mismatch.json"
expect "extra phase block" "$tmp/mismatch.json" 'v["mode"]' 'full-build'
expect "extra phase reason" "$tmp/mismatch.json" \
  '"cannot be reconciled" in v["legacy"]["error"]' 'True'
legacy_page '2' '1=0/2' '3=0/1' > "$mismatch/artifacts/infographic.html"
inspect "$mismatch" "$tmp/mismatch-keys.json"
expect "renamed phase block" "$tmp/mismatch-keys.json" \
  'v["legacy"]["error"].startswith("legacy page shows phase blocks")' 'True'
legacy_page '0/2' '1=0/2' '2=0/1' | sed '$d' | sed 's#</section>$##' > "$mismatch/artifacts/infographic.html"
cp "$tmp/legacy/tasks.md" "$mismatch/tasks.md"
inspect "$mismatch" "$tmp/truncated.json"
expect "truncated page" "$tmp/truncated.json" '"incomplete" in v["legacy"]["error"]' 'True'

# 7 — semantic refresh with a bounded exact patch for prose that has no leaf.
sed -i.bak 's/^Old goal sentence\.$/New goal sentence./' "$legacy/plan.md"
rm "$legacy/plan.md.bak"
inspect "$legacy" "$tmp/semantic.json"
expect "goal change" "$tmp/semantic.json" 'v["mode"]' 'semantic-refresh'
patch() {
  python3 - "$tmp/$1.json" "$2" <<'PY'
import json, sys
json.dump({"replacements": json.loads(sys.argv[2])}, open(sys.argv[1], "w"))
PY
}
patch good '[{"before": "<h2 class=\"goal\">Old goal sentence.</h2>", "after": "<h2 class=\"goal\">New goal sentence.</h2>"}]'
patch many "$(python3 -c 'import json; print(json.dumps([{"before": "Old goal sentence.", "after": "x"}] * 9))')"
patch repeated '[{"before": "<span>", "after": "<span class=\"x\">"}]'
patch state '[{"before": "todo-infographic-refresh-state", "after": "x"}]'
patch binding '[{"before": " data-todo-phase-count=\"phase-2\"", "after": ""}]'
patch css '[{"before": ".bar{height:4px}", "after": ".bar{height:9px}"}]'
patch missing '[{"before": "Not on the page.", "after": "x"}]'
args=(apply "$legacy" --date 2026-09-23 --status in-progress)
refused "no patch" "$html" "${args[@]}"
refused "too many replacements" "$html" "${args[@]}" --exact-patch "$tmp/many.json"
refused "non-unique before" "$html" "${args[@]}" --exact-patch "$tmp/repeated.json"
refused "state script" "$html" "${args[@]}" --exact-patch "$tmp/state.json"
refused "removed binding" "$html" "${args[@]}" --exact-patch "$tmp/binding.json"
refused "css change" "$html" "${args[@]}" --exact-patch "$tmp/css.json"
refused "absent before" "$html" "${args[@]}" --exact-patch "$tmp/missing.json"
refused "patch plus confirm" "$html" "${args[@]}" --exact-patch "$tmp/good.json" \
  --confirm-no-content-change
python3 "$refresh" "${args[@]}" --exact-patch "$tmp/good.json" > "$tmp/applied.json"
expect "exact replacements" "$tmp/applied.json" 'v["exact_replacements"]' '1'
python3 "$refresh" verify "$legacy" > /dev/null
grep -Fq '<h2 class="goal">New goal sentence.</h2>' "$html" || fail "exact patch did not land"
inspect "$legacy" "$tmp/after-patch.json"
expect "fresh after patch" "$tmp/after-patch.json" 'v["mode"]' 'fresh'

# 7b — outside semantic-refresh, --exact-patch is refused.
sed -i.bak 's/- \[ \] Legacy page\./- [x] Legacy page./' "$legacy/tasks.md"
rm "$legacy/tasks.md.bak"
patch later '[{"before": "<h2 class=\"goal\">New goal sentence.</h2>", "after": "<h2 class=\"goal\">Other.</h2>"}]'
refused "exact patch on fast refresh" "$html" "${args[@]}" --exact-patch "$tmp/later.json"

printf 'ok - infographic parser contract\n'
