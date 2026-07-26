#!/usr/bin/env bash
# Stop hook: flag superpowers plans/specs in target repos that no hub project
# references. Superpowers skills (brainstorming, writing-plans) write design docs
# into the TARGET repo (docs/superpowers/plans/ and docs/superpowers/specs/), not
# the hub — so without a recorded pointer the hub loses track of them. This hook
# scans the repos named in the active and archived registries' `repo` columns and
# blocks the stop until a pointer for each doc exists somewhere under projects/
# (convention:
# <project>/research/superpowers-docs.md).
#
# Runs on every session (plugin hook), so drift is caught both in hub sessions
# and in target-repo sessions where the docs are created.
#
# Output contract (Stop hook): emit {"decision":"block","reason":"..."} to keep
# the turn going so the agent records the pointers; emit nothing (exit 0) to allow
# the stop.
set -euo pipefail

# Resolve the hub root the same way bootstrap-hub.sh does.
HUB="${TODO_HUB:-$HOME/todo}"
case "$HUB" in "~"*) HUB="${HOME}${HUB#\~}" ;; esac
INDEX="$HUB/index.md"
ARCHIVE="$HUB/archive.md"

# If we're already inside a stop-hook continuation, don't re-trigger.
payload="$(cat 2>/dev/null || true)"
case "$payload" in
  *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) exit 0 ;;
esac

[ -f "$INDEX" ] || exit 0

# Collect unique target repos from every project row in either registry (any
# status — a doc from a completed project still deserves a pointer). Skip
# non-path values ('-', 'multi-repo').
project_rows() {
  local registry
  for registry in "$INDEX" "$ARCHIVE"; do
    [ -f "$registry" ] || continue
    grep -E '^\|' "$registry" |
      grep -Ev '^\| *short-name' |
      grep -Ev '^\|[ :|-]+\|?[ ]*$' ||
      true
  done
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

temp_dir="$(mktemp -d)"
trap "rm -rf '$temp_dir'" EXIT
repos_file="$temp_dir/repos"
untracked_file="$temp_dir/untracked"
: > "$repos_file"
: > "$untracked_file"

while IFS='|' read -r _ _shortname _path repo _status _rest; do
  repo="$(trim "$repo")"
  case "$repo" in "~/"*|"/"*) ;; *) continue ;; esac
  repo="${repo/#\~/$HOME}"
  [ -d "$repo/docs/superpowers" ] || continue
  grep -Fxq -- "$repo" "$repos_file" 2>/dev/null ||
    printf '%s\n' "$repo" >> "$repos_file"
done < <(project_rows)

# A doc is "tracked" when its filename appears anywhere under projects/.
while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  for f in "$repo"/docs/superpowers/plans/*.md "$repo"/docs/superpowers/specs/*.md; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    grep -rqF -- "$base" "$HUB/projects" 2>/dev/null && continue
    printf '%s\n' "$f" >> "$untracked_file"
  done
done < "$repos_file"

[ -s "$untracked_file" ] || exit 0
untracked="$(paste -sd ' ' "$untracked_file")"

reason="Superpowers plan/spec doc(s) exist in target repos but are referenced nowhere in the hub (${HUB}): ${untracked}. Before ending the turn, record each one in its hub project's research/superpowers-docs.md (create the file if missing) as a bullet: absolute path + one-line summary of what it covers. Resolve which project owns each doc via the repo column in index.md or archive.md; if ownership is ambiguous, pick the active project on that repo and note the uncertainty. Then stop."

printf '{"decision":"block","reason":"%s"}\n' "$(json_escape "$reason")"
exit 0
