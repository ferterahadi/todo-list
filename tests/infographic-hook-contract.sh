#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hook="$repo_root/hooks/infographic-staleness.sh"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

expect_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  printf '%s' "$haystack" | grep -Fq -- "$needle" ||
    fail "$label: output must contain: $needle"
}

expect_not_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  if printf '%s' "$haystack" | grep -Fq -- "$needle"; then
    fail "$label: output must not contain: $needle"
  fi
}

expect_empty() {
  local label="$1"
  local haystack="$2"
  [ -z "$haystack" ] || fail "$label: expected no output, got: $haystack"
}

# Every non-empty output must be one JSON object that Claude Code and Codex both accept.
expect_hook_json() {
  local label="$1"
  local output="$2"
  python3 -c '
import json, sys
value = json.loads(sys.argv[1])
allowed = {"continue", "decision", "reason", "stopReason", "suppressOutput", "systemMessage"}
assert isinstance(value, dict) and value and set(value) <= allowed, value
assert value.get("decision") in (None, "block"), value
assert ("decision" in value) == ("reason" in value), value
' "$output" || fail "$label: hook output is not a valid Stop-hook object: $output"
}

run_hook() {
  local cwd="$1"
  local session_id="${2:-session-default}"
  local transcript="$transcripts/$session_id.jsonl"
  [ -f "$transcript" ] || printf '{}\n' > "$transcript"
  local payload="{\"session_id\":\"$session_id\",\"transcript_path\":\"$transcript\"}"
  printf '%s' "$payload" |
    TODO_HUB="$hub" \
    TODO_INFOGRAPHIC_HOOK_STATE_DIR="$state_dir" \
    CLAUDE_PROJECT_DIR="$cwd" \
    bash "$hook"
}

[ -f "$hook" ] || fail "staleness hook is missing"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/todo-infographic-hook.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

hub="$tmp/hub"
alpha_repo="$tmp/repos/alpha-repo"
beta_repo="$tmp/repos/beta-repo"
elsewhere="$tmp/elsewhere"
transcripts="$tmp/transcripts"
state_dir="$tmp/state"
mkdir -p \
  "$hub/projects/work/alpha/artifacts" \
  "$hub/projects/work/beta/artifacts" \
  "$hub/projects/work/gamma" \
  "$hub/projects/work/delta/artifacts" \
  "$alpha_repo" \
  "$tmp/repos/alpha-repo-wt/alpha" \
  "$elsewhere" \
  "$transcripts"

real_plan() {
  printf '# Project: %s\n\n## Goal\nA concrete observable goal.\n' "$1"
}
real_tasks() {
  printf '# Tasks\n\n## Tasks\n- [ ] Do the thing\n'
}

real_plan alpha > "$hub/projects/work/alpha/plan.md"
real_tasks > "$hub/projects/work/alpha/tasks.md"
real_plan beta > "$hub/projects/work/beta/plan.md"
real_tasks > "$hub/projects/work/beta/tasks.md"
printf '# Project: gamma\n\n## Goal\nWhat success looks like in one sentence.\n' \
  > "$hub/projects/work/gamma/plan.md"
real_tasks > "$hub/projects/work/gamma/tasks.md"
real_plan delta > "$hub/projects/work/delta/plan.md"
real_tasks > "$hub/projects/work/delta/tasks.md"

cat > "$hub/index.md" <<INDEX
# Project Index

## Work

| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |
|---|---|---|---|---|---|---|---|---|
| alpha | projects/work/alpha | $alpha_repo | ready | - | - | - | - | - |
| beta | projects/work/beta | $beta_repo | in-progress | - | - | - | - | - |
| gamma | projects/work/gamma | - | ready | - | - | - | - | - |
| delta | projects/work/delta | $alpha_repo | done | - | - | - | - | - |
INDEX

# Inputs that predate the session are stale globally but unrelated to this turn.
touch -t 202001010000 \
  "$hub/projects/work/alpha/plan.md" "$hub/projects/work/alpha/tasks.md" \
  "$hub/projects/work/beta/plan.md" "$hub/projects/work/beta/tasks.md"

# 1 — a hub session stays silent for stale projects untouched this session.
out="$(run_hook "$hub" session-old-staleness)"
expect_empty "old hub staleness" "$out"

# 2 — a source changed during a hub session is reported; stubs and done stay out.
printf '{}\n' > "$transcripts/session-hub-change.jsonl"
sleep 1
touch "$hub/projects/work/alpha/plan.md" "$hub/projects/work/beta/tasks.md"
out="$(run_hook "$hub" session-hub-change)"
expect_hook_json "hub session change" "$out"
# A missing page needs a full build, which a hook never starts: notice, no block.
expect_contains "hub session change" "$out" '"systemMessage"'
expect_not_contains "hub session change" "$out" '"decision"'
expect_contains "hub session change" "$out" '/todo-infographic alpha'
expect_contains "hub session change" "$out" '/todo-infographic beta'
expect_contains "hub session change" "$out" 'full-build needed'
expect_not_contains "hub session change" "$out" 'gamma'
expect_not_contains "hub session change" "$out" 'delta'
expect_not_contains "focused hook message" "$out" 'repo-wide staleness scan'

# 3 — the same source revision is reported only once per session.
out="$(run_hook "$hub" session-hub-change)"
expect_empty "repeat source revision" "$out"

# A later edit is a new revision and may be reported again in that session.
sleep 1
touch "$hub/projects/work/alpha/plan.md"
out="$(run_hook "$hub" session-hub-change)"
expect_contains "new source revision" "$out" 'alpha'
expect_not_contains "new source revision" "$out" 'beta'

# 4 — a target-repo session reports only its matching project after a new edit.
printf '{}\n' > "$transcripts/session-target-repo.jsonl"
sleep 1
touch "$hub/projects/work/alpha/tasks.md" "$hub/projects/work/beta/tasks.md"
out="$(run_hook "$alpha_repo" session-target-repo)"
expect_contains "target-repo session" "$out" 'alpha'
expect_not_contains "target-repo session" "$out" 'beta'

# 5 — a session inside the project's -wt worktree counts as its repo.
out="$(run_hook "$tmp/repos/alpha-repo-wt/alpha" session-worktree)"
expect_empty "worktree without current edit" "$out"
printf '{}\n' > "$transcripts/session-worktree-edit.jsonl"
sleep 1
touch "$hub/projects/work/alpha/tasks.md"
out="$(run_hook "$tmp/repos/alpha-repo-wt/alpha" session-worktree-edit)"
expect_contains "worktree session" "$out" 'alpha'
expect_not_contains "worktree session" "$out" 'beta'

# 6 — unrelated repos stay silent.
out="$(run_hook "$elsewhere" session-elsewhere)"
expect_empty "unrelated session" "$out"

# 7 — stop-hook continuations never re-trigger.
out="$(printf '{"stop_hook_active":true}' | \
  TODO_HUB="$hub" CLAUDE_PROJECT_DIR="$hub" bash "$hook")"
expect_empty "stop-hook continuation" "$out"

# 8 — a fresh infographic (newer than plan and tasks) is not stale.
printf '<html></html>\n' > "$hub/projects/work/alpha/artifacts/infographic.html"
out="$(run_hook "$hub" session-fresh)"
expect_not_contains "fresh infographic" "$out" 'alpha'

# 9 — a new plan edit after an older infographic is stale again.
touch -t 202001010000 "$hub/projects/work/alpha/artifacts/infographic.html"
printf '{}\n' > "$transcripts/session-new-edit.jsonl"
sleep 1
touch "$hub/projects/work/alpha/plan.md"
out="$(run_hook "$hub" session-new-edit)"
expect_hook_json "stale after plan edit" "$out"
expect_contains "stale after plan edit" "$out" '/todo-infographic alpha'
expect_not_contains "unmarked page is never rebuilt by the hook" "$out" '"decision"'

# 10 — missing session identity/transcript fails quiet instead of scanning globally.
out="$(printf '{}' | TODO_HUB="$hub" CLAUDE_PROJECT_DIR="$hub" bash "$hook")"
expect_empty "missing session context" "$out"

# 11 — no hub at TODO_HUB means silence, not an error.
out="$(printf '{}' | TODO_HUB="$tmp/nohub" CLAUDE_PROJECT_DIR="$hub" bash "$hook")"
expect_empty "missing hub" "$out"

# 12 — helper modes. epsilon has an initialized, marked page; its registry
# cells are wrapped in backticks, and a row with a `..` path must be ignored.
eps="$hub/projects/work/epsilon"
mkdir -p "$eps/artifacts"
cat > "$eps/plan.md" <<'PLAN'
# Project: epsilon

## Goal
Keep a generated page current.

## Context
The page is refreshed from marked values.

## Relationships
- Depends on: nothing yet.

## Key Decisions
1. **D1 — Preserve the theme.** Refresh content only.
PLAN
cat > "$eps/tasks.md" <<'TASKS'
# Tasks

## Tasks

### Phase 1 — Foundation
- [x] Add stable bindings.
- [ ] Add the refresh helper.

### Phase 2 — Verification
- [ ] Test checkbox-only updates.
TASKS
cat > "$eps/artifacts/infographic.html" <<'HTML'
<!doctype html>
<html>
<head><style>.bar { height: 4px; }</style></head>
<body>
  <div data-todo-value="project-status">ready</div>
  <div data-todo-value="phase-count">0</div>
  <div data-todo-value="task-summary">0 done / 0</div>
  <div data-todo-value="generated-date">1970-01-01</div>
  <p data-todo-content="goal">Keep a generated page current.</p>
  <span data-todo-review-id="D1">D1</span>
  <section>
    <span data-todo-phase-count="phase-1">0/0</span>
    <div class="bar" data-todo-phase-progress="phase-1" style="width: 0%"></div>
  </section>
  <section>
    <span data-todo-phase-count="phase-2">0/0</span>
    <div class="bar" data-todo-phase-progress="phase-2" style="width: 0%"></div>
  </section>
  <aside data-todo-content="note">The page is refreshed from marked values.</aside>
</body>
</html>
HTML
refresh="$repo_root/skills/todo-infographic/scripts/refresh-infographic.py"
python3 "$refresh" inspect "$eps" --status in-progress --date 2026-01-01 \
  --output "$tmp/eps.json" >/dev/null
python3 "$refresh" migrate "$eps" --status in-progress --date 2026-01-01 \
  --manifest "$tmp/eps.json" --confirm-content-current >/dev/null
touch -t 202001010000 "$eps/plan.md" "$eps/tasks.md"
mkdir -p "$tmp/outside"
cp "$eps/plan.md" "$eps/tasks.md" "$tmp/outside/"
cat >> "$hub/index.md" <<INDEX
| \`epsilon\` | \`projects/work/epsilon\` | $alpha_repo | \`in-progress\` | - | - | - | - | - |
| escape | projects/work/../../../outside | $alpha_repo | in-progress | - | - | - | - | - |
INDEX

# 12a — a checkbox tick is a fast refresh: applied and verified silently.
printf '{}\n' > "$transcripts/session-fast.jsonl"
sleep 1
sed -i.bak 's/- \[ \] Add the refresh helper\./- [x] Add the refresh helper./' "$eps/tasks.md"
rm "$eps/tasks.md.bak"
touch "$tmp/outside/tasks.md"
started=$SECONDS
out="$(run_hook "$alpha_repo" session-fast)"
[ $((SECONDS - started)) -lt 15 ] || fail "fast refresh exceeded the 15s Stop-hook timeout"
expect_empty "fast refresh is silent (and the .. row is ignored)" "$out"
grep -Fq 'data-todo-value="task-summary">2 done / 3<' "$eps/artifacts/infographic.html" ||
  fail "hook fast refresh did not update the page"
python3 "$refresh" verify "$eps" >/dev/null || fail "hook fast refresh left the page unverifiable"

# 12b — a change only in an unrendered plan section is still a silent fast refresh.
printf '{}\n' > "$transcripts/session-hidden.jsonl"
sleep 1
sed -i.bak 's/Depends on: nothing yet\./Depends on: alpha./' "$eps/plan.md"
rm "$eps/plan.md.bak"
out="$(run_hook "$alpha_repo" session-hidden)"
expect_empty "unrendered section change" "$out"
python3 "$refresh" inspect "$eps" --status in-progress --output "$tmp/eps-hidden.json" >/dev/null
grep -Fq '"mode": "fresh"' "$tmp/eps-hidden.json" || fail "hidden-section refresh did not land"

# 12c — rendered prose drift blocks, naming only that project and the inline patch.
printf '{}\n' > "$transcripts/session-semantic.jsonl"
sleep 1
sed -i.bak 's/The page is refreshed from marked values\./The page is refreshed from compact patches./' "$eps/plan.md"
rm "$eps/plan.md.bak"
before="$(cat "$eps/artifacts/infographic.html")"
out="$(run_hook "$alpha_repo" session-semantic)"
expect_hook_json "semantic refresh" "$out"
expect_contains "semantic refresh" "$out" '"decision":"block"'
expect_contains "semantic refresh" "$out" 'epsilon'
expect_contains "semantic refresh" "$out" 'small inline prose patch'
expect_contains "semantic refresh" "$out" 'Do not start a full build or legacy migration'
expect_not_contains "semantic refresh" "$out" 'alpha'
[ "$before" = "$(cat "$eps/artifacts/infographic.html")" ] ||
  fail "semantic refresh changed the page without a patch"
out="$(run_hook "$alpha_repo" session-semantic)"
expect_empty "semantic block is reported once per revision" "$out"

# 12d — a helper error is a notice that names the explicit command, never a block.
fake_python="$tmp/fake-python"
cat > "$fake_python" <<'FAKE'
#!/usr/bin/env bash
printf 'ERROR\tboom "quoted" \\ path\n' >&2
exit 2
FAKE
chmod +x "$fake_python"
printf '{}\n' > "$transcripts/session-error.jsonl"
sleep 1
touch "$eps/tasks.md"
out="$(TODO_INFOGRAPHIC_PYTHON="$fake_python" run_hook "$alpha_repo" session-error)"
expect_hook_json "helper error" "$out"
expect_contains "helper error" "$out" 'helper error: boom'
expect_contains "helper error" "$out" '/todo-infographic epsilon'
expect_not_contains "helper error" "$out" '"decision"'

# 12e — past the time budget, remaining projects become notices instead of work.
printf '{}\n' > "$transcripts/session-budget.jsonl"
sleep 1
touch "$eps/tasks.md"
out="$(TODO_INFOGRAPHIC_HOOK_BUDGET_SECONDS=0 run_hook "$alpha_repo" session-budget)"
expect_hook_json "time budget" "$out"
expect_contains "time budget" "$out" 'time limit'
expect_contains "time budget" "$out" '/todo-infographic epsilon'

# 12f — a block and a notice in the same stop share one object.
printf '{}\n' > "$transcripts/session-mixed.jsonl"
sleep 1
touch "$eps/plan.md" "$hub/projects/work/alpha/tasks.md"
out="$(run_hook "$alpha_repo" session-mixed)"
expect_hook_json "block with notice" "$out"
expect_contains "block with notice" "$out" '"decision":"block"'
expect_contains "block with notice" "$out" '"systemMessage"'
expect_contains "block with notice" "$out" '/todo-infographic alpha'

printf 'ok - infographic staleness hook contract\n'
