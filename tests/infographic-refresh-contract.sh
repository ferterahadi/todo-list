#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
refresh="$repo_root/skills/todo-infographic/scripts/refresh-infographic.py"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

expect_mode() {
  local expected="$1"
  local manifest="$2"
  local actual
  actual="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["mode"])' "$manifest")"
  [ "$actual" = "$expected" ] || fail "expected mode $expected, got $actual"
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/todo-infographic-refresh.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
project="$tmp/project"
html="$project/artifacts/infographic.html"
mkdir -p "$project/artifacts"

cat > "$project/plan.md" <<'PLAN'
# Project: Fast infographic

## Goal
Keep a generated page current.

## Context
The page is refreshed from marked values.

## Key Decisions
1. **D1 — Preserve the theme.** Refresh content only.
2. **D2 — Derive progress.** Count real task checkboxes.
PLAN

cat > "$project/tasks.md" <<'TASKS'
# Tasks

## Phase 1 — Foundation
- [x] Add stable bindings.
- [ ] Add the refresh helper.

## Phase 2 — Verification
- [ ] Test checkbox-only updates.

## Notes
- [x] This documentation checkbox is not a task.
TASKS

cat > "$html" <<'HTML'
<!doctype html>
<html>
<head><style>.bar { height: 4px; } .accent { color: #2457ff; }</style></head>
<body>
  <div data-todo-value="project-status">ready</div>
  <div data-todo-value="phase-count">0</div>
  <div data-todo-value="task-summary">0 done / 0</div>
  <div data-todo-value="task-done">0</div>
  <div data-todo-value="task-total">0</div>
  <div data-todo-value="task-open">0</div>
  <div data-todo-value="generated-date">1970-01-01</div>
  <section>
    <span data-todo-review-id="D1">D1</span>
    <span data-todo-review-id="D2">D2</span>
  </section>
  <section data-phase="phase-1">
    <span data-todo-phase-count="phase-1">0/0</span>
    <div class="bar" data-todo-phase-progress="phase-1" style="width: 0%"></div>
    <p data-todo-content="phase:phase-1">Old phase summary.</p>
  </section>
  <section data-phase="phase-2">
    <span data-todo-phase-count="phase-2">0/0</span>
    <div class="bar" data-todo-phase-progress="phase-2" style="width: 0%"></div>
    <p data-todo-content="phase:phase-2">Old verification summary.</p>
  </section>
  <aside data-todo-content="note">Old note.</aside>
</body>
</html>
HTML

python3 "$refresh" inspect "$project" --html "$html" --date 2026-09-18 \
  --status in-progress --output "$tmp/legacy.json"
expect_mode legacy-migration "$tmp/legacy.json"

css_before="$(python3 - "$html" <<'PY'
import hashlib,re,sys
s=open(sys.argv[1], encoding='utf-8').read()
print(hashlib.sha256('\n'.join(re.findall(r'<style\b[^>]*>(.*?)</style\s*>', s, re.I|re.S)).encode()).hexdigest())
PY
)"

if python3 "$refresh" migrate "$project" --html "$html" --date 2026-09-18 \
  --status in-progress --manifest "$tmp/legacy.json" > "$tmp/unexpected-unreviewed.json" 2>/dev/null; then
  fail "legacy migration initialized state without a semantic review decision"
fi
python3 "$refresh" migrate "$project" --html "$html" --date 2026-09-18 \
  --status in-progress --manifest "$tmp/legacy.json" --confirm-content-current \
  > "$tmp/initialized.json"
python3 "$refresh" verify "$project" --html "$html" > "$tmp/verified.json"
grep -Fq 'data-todo-value="task-summary">1 done / 3<' "$html" ||
  fail "initialization did not write the total"
grep -Fq 'data-todo-phase-count="phase-1">1/2<' "$html" ||
  fail "initialization did not write the phase count"
grep -Fq 'data-todo-phase-progress="phase-1" style="width: 50%"' "$html" ||
  fail "initialization did not write the phase width"

python3 "$refresh" inspect "$project" --html "$html" --date 2026-09-18 \
  --status in-progress --output "$tmp/fresh.json"
expect_mode fresh "$tmp/fresh.json"

sed -i.bak 's/- \[ \] Add the refresh helper\./- [x] Add the refresh helper./' "$project/tasks.md"
rm "$project/tasks.md.bak"
python3 "$refresh" inspect "$project" --html "$html" --date 2026-09-18 \
  --status in-progress --output "$tmp/fast.json"
expect_mode fast-refresh "$tmp/fast.json"
python3 "$refresh" apply "$project" --html "$html" --date 2026-09-18 \
  --status in-progress > "$tmp/fast-applied.json"
grep -Fq 'data-todo-value="task-summary">2 done / 3<' "$html" ||
  fail "fast refresh did not update the total"
grep -Fq 'data-todo-phase-progress="phase-1" style="width: 100%"' "$html" ||
  fail "fast refresh did not update the phase width"

python3 - "$project/plan.md" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1])
s=p.read_text()
p.write_text(s.replace('The page is refreshed from marked values.', 'The page is refreshed from compact semantic patches.'))
PY
python3 "$refresh" inspect "$project" --html "$html" --date 2026-09-18 \
  --status in-progress --output "$tmp/semantic.json"
expect_mode semantic-refresh "$tmp/semantic.json"
grep -Fq '"name": "Context"' "$tmp/semantic.json" ||
  fail "semantic manifest did not identify the changed section"
if python3 "$refresh" apply "$project" --html "$html" --date 2026-09-18 \
  --status in-progress > "$tmp/unexpected.json" 2>/dev/null; then
  fail "semantic refresh applied without an explicit content decision"
fi
cat > "$tmp/patch.json" <<'JSON'
{"content":{"note":"Compact semantic patch applied."}}
JSON
python3 "$refresh" apply "$project" --html "$html" --date 2026-09-18 \
  --status in-progress --content-patch "$tmp/patch.json" > "$tmp/semantic-applied.json"
grep -Fq 'data-todo-content="note">Compact semantic patch applied.<' "$html" ||
  fail "semantic refresh did not update the marked prose"
python3 "$refresh" verify "$project" --html "$html" > "$tmp/semantic-verified.json"

css_after="$(python3 - "$html" <<'PY'
import hashlib,re,sys
s=open(sys.argv[1], encoding='utf-8').read()
print(hashlib.sha256('\n'.join(re.findall(r'<style\b[^>]*>(.*?)</style\s*>', s, re.I|re.S)).encode()).hexdigest())
PY
)"
[ "$css_before" = "$css_after" ] || fail "refresh changed the CSS"

python3 - "$project/plan.md" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1])
s=p.read_text()
p.write_text(s.replace('2. **D2 — Derive progress.** Count real task checkboxes.', '2. **D2 — Derive progress.** Count real task checkboxes.\n3. **D3 — Keep structure explicit.** New cards require a design pass.'))
PY
python3 "$refresh" inspect "$project" --html "$html" --date 2026-09-18 \
  --status in-progress --output "$tmp/structural.json"
expect_mode full-build "$tmp/structural.json"
grep -Fq 'decision-card-structure-changed' "$tmp/structural.json" ||
  fail "new decision did not require a structural build"

legacy_project="$tmp/legacy-project"
legacy_html="$legacy_project/artifacts/infographic.html"
mkdir -p "$legacy_project/artifacts"
cat > "$legacy_project/plan.md" <<'PLAN'
# Project: Legacy migration

## Goal
Keep the existing visual while adding refresh bindings.

## Key Decisions
1. **D1 — Preserve CSS.** The helper owns marker insertion.
2. **D2 — Bound semantic work.** The model returns an exact fragment patch.
PLAN
cat > "$legacy_project/tasks.md" <<'TASKS'
# Tasks

## Phase 1 — Markers
- [x] Add deterministic bindings.
- [x] Initialize state.

## Phase 2 — Content
- [ ] Patch one stale fragment.
TASKS
cat > "$legacy_html" <<'HTML'
<!doctype html>
<html>
<head><style>.bar{height:4px}.card{border:1px solid}.n{font-size:2rem}</style></head>
<body>
  <section class="stats">
    <div class="stat"><span class="n">1<small>/3</small></span><span class="k">Tasks done</span></div>
    <div class="stat"><span class="n">2</span><span class="k">Phases</span></div>
  </section>
  <section class="decisions">
    <div class="card"><span>[D1]</span><p>Preserve CSS.</p><span>Gain</span><span>Stable theme.</span><span>Cost</span><span>Strict matching.</span></div>
    <div class="card"><span>[D2]</span><p>Bound semantic work.</p><span>Gain</span><span>Small prompts.</span><span>Cost</span><span>Exact patches.</span></div>
    <div class="card stale"><span>[D3]</span><p>Stale decision to remove.</p><span>Gain</span><span>None.</span><span>Cost</span><span>Wrong structure.</span></div>
  </section>
  <section class="phase"><span>Phase 1</span><span>1 / 2 done</span><div class="bar" style="width:50%"></div><span>50%</span></section>
  <section class="phase"><span>Phase 2</span><span>0 / 1 open</span><div class="bar" style="width:0%"></div><span>0%</span></section>
  <footer><span>Generated from plan.md + tasks.md · 2026-09-17</span></footer>
</body>
</html>
HTML

legacy_css_before="$(python3 - "$legacy_html" <<'PY'
import hashlib,re,sys
s=open(sys.argv[1], encoding='utf-8').read()
print(hashlib.sha256('\n'.join(re.findall(r'<style\b[^>]*>(.*?)</style\s*>', s, re.I|re.S)).encode()).hexdigest())
PY
)"
python3 "$refresh" inspect "$legacy_project" --html "$legacy_html" --date 2026-09-18 \
  --status in-progress --output "$tmp/legacy-unmarked.json"
expect_mode legacy-migration "$tmp/legacy-unmarked.json"
grep -Fq 'legacy-content-patch-required' "$tmp/legacy-unmarked.json" ||
  fail "stale decision did not require a bounded content patch"
grep -Fq '"D3"' "$tmp/legacy-unmarked.json" ||
  fail "legacy manifest did not report the stale decision"

python3 "$refresh" fragment --html "$legacy_html" --needle '[D3]' \
  --contains Gain --contains Cost --output "$tmp/stale-fragment.json"
python3 - "$tmp/stale-fragment.json" "$tmp/exact-patch.json" <<'PY'
import json,sys
fragment=json.load(open(sys.argv[1], encoding='utf-8'))['fragment']
json.dump({'replacements':[{'before':fragment,'after':''}]}, open(sys.argv[2], 'w', encoding='utf-8'))
PY
cp "$legacy_html" "$tmp/legacy-html.before"
python3 - "$legacy_html" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
p.write_text(p.read_text().replace('Small prompts.', 'Small focused prompts.'), encoding='utf-8')
PY
if python3 "$refresh" migrate "$legacy_project" --html "$legacy_html" --date 2026-09-18 \
  --status in-progress --manifest "$tmp/legacy-unmarked.json" \
  --exact-patch "$tmp/exact-patch.json" > "$tmp/unexpected-html-drift.json" 2>/dev/null; then
  fail "legacy migration accepted HTML changed after inspection"
fi
cp "$tmp/legacy-html.before" "$legacy_html"
cp "$legacy_project/tasks.md" "$tmp/legacy-tasks.before"
printf '\n' >> "$legacy_project/tasks.md"
if python3 "$refresh" migrate "$legacy_project" --html "$legacy_html" --date 2026-09-18 \
  --status in-progress --manifest "$tmp/legacy-unmarked.json" \
  --exact-patch "$tmp/exact-patch.json" > "$tmp/unexpected-stale-migration.json" 2>/dev/null; then
  fail "legacy migration accepted a source edit made after inspection"
fi
cp "$tmp/legacy-tasks.before" "$legacy_project/tasks.md"
python3 "$refresh" migrate "$legacy_project" --html "$legacy_html" --date 2026-09-18 \
  --status in-progress --manifest "$tmp/legacy-unmarked.json" \
  --exact-patch "$tmp/exact-patch.json" > "$tmp/legacy-migrated.json"
python3 "$refresh" verify "$legacy_project" --html "$legacy_html" > "$tmp/legacy-verified.json"
grep -Fq 'data-todo-value="task-done">2<' "$legacy_html" ||
  fail "legacy migration did not wrap the completed task count"
grep -Fq 'data-todo-value="task-total">3<' "$legacy_html" ||
  fail "legacy migration did not wrap the total task count"
grep -Fq 'data-todo-phase-count="phase-1"' "$legacy_html" ||
  fail "legacy migration did not bind the phase count"
grep -Fq 'data-todo-phase-progress="phase-2"' "$legacy_html" ||
  fail "legacy migration did not bind the phase progress"
grep -Fq 'data-todo-phase-percent="phase-1">100%<' "$legacy_html" ||
  fail "legacy migration left the visible phase percent stale"
grep -Fq 'data-todo-review-id="D2"' "$legacy_html" ||
  fail "legacy migration did not bind the decision card"
if grep -Fq '[D3]' "$legacy_html"; then
  fail "bounded exact patch did not remove the stale decision"
fi
grep -Fq 'data-todo-value="generated-date">2026-09-18<' "$legacy_html" ||
  fail "legacy migration did not update an older generated date"
legacy_css_after="$(python3 - "$legacy_html" <<'PY'
import hashlib,re,sys
s=open(sys.argv[1], encoding='utf-8').read()
print(hashlib.sha256('\n'.join(re.findall(r'<style\b[^>]*>(.*?)</style\s*>', s, re.I|re.S)).encode()).hexdigest())
PY
)"
[ "$legacy_css_before" = "$legacy_css_after" ] || fail "legacy migration changed CSS bytes"

printf 'ok - infographic refresh contract\n'
