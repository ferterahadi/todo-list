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

run_hook() {
  local cwd="$1"
  local payload="${2:-{\}}"
  printf '%s' "$payload" |
    TODO_HUB="$hub" CLAUDE_PROJECT_DIR="$cwd" bash "$hook"
}

[ -f "$hook" ] || fail "staleness hook is missing"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/todo-infographic-hook.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

hub="$tmp/hub"
alpha_repo="$tmp/repos/alpha-repo"
beta_repo="$tmp/repos/beta-repo"
elsewhere="$tmp/elsewhere"
mkdir -p \
  "$hub/projects/work/alpha/artifacts" \
  "$hub/projects/work/beta/artifacts" \
  "$hub/projects/work/gamma" \
  "$hub/projects/work/delta/artifacts" \
  "$alpha_repo" \
  "$tmp/repos/alpha-repo-wt/alpha" \
  "$elsewhere"

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

# 1 — hub session reports every stale ready/in-progress project, skips stubs and done.
out="$(run_hook "$hub")"
expect_contains "hub session" "$out" '"decision":"block"'
expect_contains "hub session" "$out" 'alpha'
expect_contains "hub session" "$out" 'beta'
expect_not_contains "hub session" "$out" 'gamma'
expect_not_contains "hub session" "$out" 'delta'

# 2 — a session inside a project's target repo reports only that project.
out="$(run_hook "$alpha_repo")"
expect_contains "target-repo session" "$out" 'alpha'
expect_not_contains "target-repo session" "$out" 'beta'

# 3 — a session inside the project's -wt worktree counts as its repo.
out="$(run_hook "$tmp/repos/alpha-repo-wt/alpha")"
expect_contains "worktree session" "$out" 'alpha'
expect_not_contains "worktree session" "$out" 'beta'

# 4 — unrelated repos stay silent.
out="$(run_hook "$elsewhere")"
expect_empty "unrelated session" "$out"

# 5 — stop-hook continuations never re-trigger.
out="$(run_hook "$hub" '{"stop_hook_active":true}')"
expect_empty "stop-hook continuation" "$out"

# 6 — a fresh infographic (newer than plan and tasks) is not stale.
touch -t 202001010000 \
  "$hub/projects/work/alpha/plan.md" "$hub/projects/work/alpha/tasks.md"
printf '<html></html>\n' > "$hub/projects/work/alpha/artifacts/infographic.html"
out="$(run_hook "$hub")"
expect_contains "fresh infographic" "$out" 'beta'
expect_not_contains "fresh infographic" "$out" 'alpha'

# 7 — an infographic older than plan.md is stale again.
touch -t 202001010000 "$hub/projects/work/alpha/artifacts/infographic.html"
touch "$hub/projects/work/alpha/plan.md"
out="$(run_hook "$hub")"
expect_contains "stale after plan edit" "$out" 'alpha'

# 8 — no hub at TODO_HUB means silence, not an error.
out="$(printf '{}' | TODO_HUB="$tmp/nohub" CLAUDE_PROJECT_DIR="$hub" bash "$hook")"
expect_empty "missing hub" "$out"

printf 'ok - infographic staleness hook contract\n'
