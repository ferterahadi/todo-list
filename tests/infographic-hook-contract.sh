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
expect_contains "hub session change" "$out" '"decision":"block"'
expect_contains "hub session change" "$out" 'alpha'
expect_contains "hub session change" "$out" 'beta'
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
expect_contains "stale after plan edit" "$out" 'alpha'

# 10 — missing session identity/transcript fails quiet instead of scanning globally.
out="$(printf '{}' | TODO_HUB="$hub" CLAUDE_PROJECT_DIR="$hub" bash "$hook")"
expect_empty "missing session context" "$out"

# 11 — no hub at TODO_HUB means silence, not an error.
out="$(printf '{}' | TODO_HUB="$tmp/nohub" CLAUDE_PROJECT_DIR="$hub" bash "$hook")"
expect_empty "missing hub" "$out"

printf 'ok - infographic staleness hook contract\n'
