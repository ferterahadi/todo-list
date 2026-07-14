#!/usr/bin/env bash
# Stop hook: nudge Claude to (re)generate one-pager infographics that are missing
# or stale. A project's artifacts/infographic.html is "stale" when plan.md or
# tasks.md is newer than it. Only projects with status ready / in-progress and a
# real (non-stub) plan.md are considered — done projects are left alone.
#
# Output contract (Stop hook): emit {"decision":"block","reason":"..."} to keep the
# turn going so Claude regenerates; emit nothing (exit 0) to allow the stop.
set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
INDEX="$ROOT/index.md"

# Read the hook payload; if we're already inside a stop-hook continuation, don't
# re-trigger — avoids a loop if generation ever fails to refresh the file.
payload="$(cat 2>/dev/null || true)"
case "$payload" in
  *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) exit 0 ;;
esac

[ -f "$INDEX" ] || exit 0

# Portable mtime (BSD/macOS then GNU/Linux).
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

stale=""
# Pull "path|status" for every project row in index.md (skips header/separator rows).
while IFS='|' read -r _ shortname path repo status _rest; do
  shortname="$(echo "$shortname" | xargs)"
  path="$(echo "$path" | xargs)"
  status="$(echo "$status" | xargs)"
  case "$status" in
    ready|in-progress) ;;
    *) continue ;;
  esac
  plan="$ROOT/$path/plan.md"
  tasks="$ROOT/$path/tasks.md"
  info="$ROOT/$path/artifacts/infographic.html"

  [ -f "$plan" ] || continue
  # Skip unfilled template stubs.
  grep -q "What success looks like in one sentence." "$plan" 2>/dev/null && continue

  if [ ! -f "$info" ]; then
    stale="$stale $shortname"
    continue
  fi
  it="$(mtime "$info")"
  pt="$(mtime "$plan")"
  tt="$(mtime "$tasks")"
  if [ "$pt" -gt "$it" ] || [ "$tt" -gt "$it" ]; then
    stale="$stale $shortname"
  fi
done < <(grep -E '^\|' "$INDEX" | grep -Ev '^\| *short-name' | grep -Ev '^\|[ :|-]+\|?[ ]*$')

stale="$(echo "$stale" | xargs)"
[ -z "$stale" ] && exit 0

reason="One-pager infographic(s) are missing or out of date for: ${stale}. \
This is a repo-wide staleness scan, NOT a scope instruction. Regenerate ONLY the \
listed project(s) you actually worked on in this session, by invoking the \
todo-infographic skill (it reads plan.md + tasks.md, writes \
artifacts/infographic.html, and updates the project's infographic column in \
index.md). Leave listed projects you did not touch this session alone — do NOT \
regenerate all of them. If none of the listed projects relate to this session, \
just stop without generating anything."

# Emit the block decision as JSON (printf keeps it valid without jq).
printf '{"decision":"block","reason":"%s"}\n' "$reason"
exit 0
